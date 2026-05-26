# syntax=docker/dockerfile:1.7

# ---------------------------------------------------------------------------
# Stage 1: build the extension/provider jars from libs/ with Maven.
#
# Runs on the native BUILDPLATFORM (jars are architecture-independent) so
# multi-arch builds are not slowed down by qemu emulation of the JVM. Uses
# a BuildKit cache mount for ~/.m2 to keep incremental rebuilds fast.
# ---------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM maven:3.9-eclipse-temurin-21 AS libs-builder

WORKDIR /build

# Bring in just the poms first so dependency resolution layer can be cached
# independently of the (rarely-changed) Java sources.
COPY libs/pom.xml ./pom.xml
COPY libs/internal/pom.xml ./internal/pom.xml
COPY libs/bundle/pom.xml ./bundle/pom.xml

RUN --mount=type=cache,target=/root/.m2,sharing=locked \
    mvn -B -e --strict-checksums -ntp \
        -pl . -am dependency:go-offline -DskipTests || true

COPY libs/ ./

RUN --mount=type=cache,target=/root/.m2,sharing=locked \
    mvn -B -e --strict-checksums -ntp clean package -DskipTests

# ---------------------------------------------------------------------------
# Stage 2: Keycloak builder. Stages the providers and runs `kc.sh build` so
# the runtime image can launch with `start --optimized` (no augmentation).
# ---------------------------------------------------------------------------
FROM quay.io/phasetwo/keycloak-crdb:26.6.2 AS keycloak-builder

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

# JVM hardening — bound heap to container memory, fail-fast on OOM, capture a
# heap dump for postmortem analysis, and use a non-blocking entropy source so
# startup never stalls waiting on /dev/random.
ENV JAVA_OPTS_APPEND="\
-XX:+ExitOnOutOfMemoryError \
-XX:+HeapDumpOnOutOfMemoryError \
-XX:HeapDumpPath=/tmp/heap.hprof \
-XX:MaxRAMPercentage=70 \
-XX:InitialRAMPercentage=50 \
-XX:MetaspaceSize=96M \
-XX:MaxMetaspaceSize=256m \
-Djava.security.egd=file:/dev/urandom \
-Djava.awt.headless=true \
-Dfile.encoding=UTF-8"

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
