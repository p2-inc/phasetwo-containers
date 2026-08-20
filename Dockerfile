# syntax=docker/dockerfile:1.7

# ---------------------------------------------------------------------------
# Default named context: empty layer that satisfies the `from=host-m2` bind
# mount below when no `--build-context host-m2=...` flag is supplied (CI).
#
# To test against a SNAPSHOT in your host's ~/.m2, override the context with
# a directory whose layout mirrors ~/.m2 (i.e. contains a `repository/`
# subdir):
#
#     docker buildx build --build-context host-m2=$HOME/.m2 .
#
# BuildKit copies the entire host context into its filesystem before the
# build runs, so a large ~/.m2 (multiple GB) can be slow and may exhaust
# Docker's disk. For faster local testing, stage just the SNAPSHOTs you
# need:
#
#     mkdir -p /tmp/scim-m2/repository/io/phasetwo
#     cp -r ~/.m2/repository/io/phasetwo/keycloak \
#           /tmp/scim-m2/repository/io/phasetwo/
#     docker buildx build --build-context host-m2=/tmp/scim-m2 .
#
# ---------------------------------------------------------------------------
FROM scratch AS host-m2

# ---------------------------------------------------------------------------
# Default named context for the Keycloak server distribution and its Maven
# artifacts, built from source by scripts/build-keycloak.sh.
#
# Keycloak tags patch releases without publishing jars to Maven Central or
# images to quay.io (26.6.5 and 26.6.6, for example), so there is no base image
# to start `FROM` and no `org.keycloak:*` jars for libs/ to compile against.
# Both come out of a source build of p2-inc/keycloak branch `<version>_crdb`:
#
#     scripts/build-keycloak.sh
#     docker buildx build --build-context keycloak=.keycloak-build/out .
#
# The context is expected to contain:
#
#     dist/keycloak-<version>.tar.gz          the server distribution
#     dist/cockroachdb-jdbc-driver-*.jar      CRDB driver, carried by the fork
#     m2/repository/org/keycloak/**           artifacts libs/ compiles against
#
# Leaving it empty is a hard error rather than a silent fall back to Central,
# so a stale image can never be built against the wrong Keycloak.
# ---------------------------------------------------------------------------
FROM scratch AS keycloak

# ---------------------------------------------------------------------------
# Stage 1: build the extension/provider jars from libs/ with Maven.
#
# Runs on the native BUILDPLATFORM (jars are architecture-independent) so
# multi-arch builds are not slowed down by qemu emulation of the JVM. Uses
# a BuildKit cache mount for ~/.m2 to keep incremental rebuilds fast.
#
# When `host-m2` is overridden via `--build-context host-m2=$HOME/.m2`, the
# host repository is overlaid onto the build's m2 cache with `cp -rf`,
# so locally-installed SNAPSHOTs always win over whatever is in the cache
# (essential for iterating on a SNAPSHOT: `cp -rn` would leave a stale
# previous build of the SNAPSHOT in the cache forever).
# ---------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM maven:3.9-eclipse-temurin-21 AS libs-builder

# Git commit SHA injected at build time. The buildnumber-maven-plugin inside
# libs/internal/pom.xml normally reads this from .git, but .git is not
# available inside the Docker build context. Passing it here lets the
# fizzed-versionizer plugin stamp the correct commit into the Version class.
ARG GIT_COMMIT=unknown

WORKDIR /build

# Bring in just the poms first so dependency resolution layer can be cached
# independently of the (rarely-changed) Java sources.
COPY libs/pom.xml ./pom.xml
COPY libs/internal/pom.xml ./internal/pom.xml
COPY libs/bundle/pom.xml ./bundle/pom.xml

RUN --mount=type=cache,target=/root/.m2,sharing=locked \
    --mount=type=bind,from=host-m2,target=/host-m2,readonly \
    --mount=type=bind,from=keycloak,target=/kc,readonly \
    mkdir -p /root/.m2/repository && \
    if [ -d /kc/m2/repository ]; then \
        cp -rf /kc/m2/repository/. /root/.m2/repository/; \
    fi && \
    if [ -d /host-m2/repository ]; then \
        cp -rf /host-m2/repository/. /root/.m2/repository/ 2>/dev/null || true; \
    fi && \
    mvn -B -e --strict-checksums -ntp \
        -pl . -am dependency:go-offline -DskipTests || true

COPY libs/ ./

RUN --mount=type=cache,target=/root/.m2,sharing=locked \
    --mount=type=bind,from=host-m2,target=/host-m2,readonly \
    --mount=type=bind,from=keycloak,target=/kc,readonly \
    if [ ! -d /kc/m2/repository/org/keycloak ]; then \
        echo "ERROR: the 'keycloak' build context has no org.keycloak artifacts." >&2; \
        echo "Run scripts/build-keycloak.sh, then pass:" >&2; \
        echo "  --build-context keycloak=.keycloak-build/out" >&2; \
        exit 1; \
    fi && \
    mkdir -p /root/.m2/repository && \
    cp -rf /kc/m2/repository/. /root/.m2/repository/ && \
    if [ -d /host-m2/repository ]; then \
        cp -rf /host-m2/repository/. /root/.m2/repository/ 2>/dev/null || true; \
    fi && \
    mvn -B -e --strict-checksums -ntp clean package -DskipTests \
        -DbuildNumber="${GIT_COMMIT}"

# ---------------------------------------------------------------------------
# Stage 2: Keycloak builder. Unpacks the source-built server distribution,
# stages the providers, and runs `kc.sh build` so the runtime image can launch
# with `start --optimized` (no augmentation).
#
# This used to start `FROM quay.io/phasetwo/keycloak-crdb:<version>`, which
# only works for versions that were actually imaged. Unpacking the tarball
# produced by scripts/build-keycloak.sh instead means any tagged Keycloak can
# be built, and drops the UBI9-micro intermediary from the critical path — the
# runtime image (stage 3) is Wolfi and never used anything else from it.
# ---------------------------------------------------------------------------
FROM eclipse-temurin:21-jdk AS keycloak-builder

# `kc.sh build` needs a JDK, tar and bash; the base image supplies all three.
RUN --mount=type=bind,from=keycloak,target=/kc,readonly \
    set -eu; \
    tarball=$(ls /kc/dist/keycloak-*.tar.gz 2>/dev/null | head -1); \
    if [ -z "$tarball" ]; then \
        echo "ERROR: no keycloak-*.tar.gz in the 'keycloak' build context." >&2; \
        echo "Run scripts/build-keycloak.sh, then pass:" >&2; \
        echo "  --build-context keycloak=.keycloak-build/out" >&2; \
        exit 1; \
    fi; \
    tar -xzf "$tarball" -C /opt; \
    mv /opt/keycloak-* /opt/keycloak; \
    mkdir -p /opt/keycloak/data; \
    for j in /kc/dist/cockroachdb-jdbc-driver-*.jar; do \
        [ -f "$j" ] || continue; \
        cp "$j" "/opt/keycloak/providers/io.cockroachdb.jdbc.$(basename "$j")"; \
    done; \
    chmod -R g+rwX /opt/keycloak

ENV KC_METRICS_ENABLED=true
ENV KC_HEALTH_ENABLED=true
ENV KC_FEATURES=preview

COPY ./conf/cache-ispn-jdbc-ping.xml /opt/keycloak/conf/cache-ispn-jdbc-ping.xml

# Pre-built third-party provider jars (checked into the repo) plus the jars
# produced by stage 1's Maven build.
COPY ./libs/ext/*.jar /opt/keycloak/providers/
COPY --from=libs-builder /build/bundle/target/bundle-*/*.jar /opt/keycloak/providers/

RUN /opt/keycloak/bin/kc.sh --verbose build \
        --spi-email-template-provider=freemarker-plus-mustache \
        --spi-email-template-freemarker-plus-mustache-enabled=true \
        --spi-theme-cache-themes=false

# ---------------------------------------------------------------------------
# Stage 3: hardened runtime image on Chainguard's Wolfi OS — minimal package
# surface, daily-rebuilt base, no leftover build tooling. Only the augmented
# Keycloak tree is carried over from the builder; everything else (JRE,
# shell, CA bundle) comes from Wolfi packages.
# ---------------------------------------------------------------------------
FROM cgr.dev/chainguard/wolfi-base:latest

LABEL org.opencontainers.image.title="phasetwo-keycloak" \
      org.opencontainers.image.source="https://github.com/p2-inc/phasetwo-containers" \
      org.opencontainers.image.licenses="Elastic-2.0" \
      org.opencontainers.image.vendor="Phase Two, Inc."

# Dedicated non-root identity for the running process. UID/GID 2000 avoids
# collisions with the UID 1000 baked into many base images and lines up with
# the article's reference numbers; overridable at build time via --build-arg
# for environments that need a specific UID.
ARG USER=keycloak
ARG UID=2000
ARG GID=2000
ENV KEYCLOAK_HOME=/opt/keycloak

# Three runtime packages only: a JRE for the JVM, bash for kc.sh, and the CA
# bundle for outbound TLS (SMTP, OIDC IdPs, webhooks, etc.). Then create the
# unprivileged account that the runtime will run as.
RUN apk add --no-cache \
        bash \
        ca-certificates-bundle \
        openjdk-21-default-jvm \
    && addgroup -g ${GID} ${USER} \
    && adduser -u ${UID} -G ${USER} -s /bin/bash -D -h ${KEYCLOAK_HOME} ${USER} \
    && rm -rf /var/cache/apk/*

ENV JAVA_HOME=/usr/lib/jvm/default-jvm \
    PATH=/usr/lib/jvm/default-jvm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8 \
    KC_RUN_IN_CONTAINER=true

# JVM hardening — only the bits upstream kc.sh doesn't already set. The
# upstream default JAVA_OPTS (see /opt/keycloak/bin/kc.sh in the base
# image) already covers `-XX:+ExitOnOutOfMemoryError`, the
# `MaxRAMPercentage / MinRAMPercentage / InitialRAMPercentage` triple, the
# `MetaspaceSize / MaxMetaspaceSize` bounds, `-Djava.security.egd=file:/dev/urandom`,
# `-Dfile.encoding=UTF-8`, G1GC, and FlightRecorder defaults — so we only
# append:
#   - HeapDumpOnOutOfMemoryError + HeapDumpPath: capture diagnostics on OOM
#   - java.awt.headless: avoid AWT init for headless container workloads
ENV JAVA_OPTS_APPEND="\
-XX:+HeapDumpOnOutOfMemoryError \
-XX:HeapDumpPath=/tmp/heap.hprof \
-Djava.awt.headless=true"

# Secure defaults: keep management/health on, but disable plaintext HTTP. Any
# deployment that needs cleartext on the pod (e.g. local docker-compose or a
# TLS-terminating sidecar that requires HTTP upstream) must set
# KC_HTTP_ENABLED=true explicitly.
ENV KC_HEALTH_ENABLED=true \
    KC_METRICS_ENABLED=true \
    KC_HTTP_ENABLED=false

# Carry the full augmented Keycloak tree from the builder — kc.sh, providers,
# lib/quarkus (post-augmentation), conf, themes, data — owned by the
# unprivileged account so nothing in the runtime layer is owned by root.
COPY --from=keycloak-builder --chown=${USER}:${USER} /opt/keycloak ${KEYCLOAK_HOME}

# Principle of least privilege: directories 755, files 644, executable
# scripts 755. Also clears any setuid/setgid bits that may have been
# inherited from upstream layers.
RUN find ${KEYCLOAK_HOME} -type d -exec chmod 755 {} + \
    && find ${KEYCLOAK_HOME} -type f -exec chmod 644 {} + \
    && chmod 755 ${KEYCLOAK_HOME}/bin/*.sh

USER ${USER}

WORKDIR ${KEYCLOAK_HOME}
EXPOSE 8080 8443 9000

# kc.sh already `exec`s the JVM so SIGTERM reaches it directly as PID 1.
# No HEALTHCHECK is declared — Kubernetes ignores Dockerfile HEALTHCHECK and
# runs its own liveness/readiness probes against /health/live and
# /health/ready, which are enabled above via KC_HEALTH_ENABLED=true.
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
