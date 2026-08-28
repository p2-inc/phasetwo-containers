> :rocket: **Try it for free** in the Phase Two [keycloak managed service](https://phasetwo.io/?utm_source=github&utm_medium=readme&utm_campaign=phasetwo-containers). Go to [Phase Two](https://phasetwo.io/) for more information.

# Phase Two Keycloak Docker image

Builds the base Phase Two Keycloak Docker image that is used in the self-serve clusters (both for shared and dedicated). This is based on the a Keycloak image which differs from the mainline with added support for [Keycloak on CockroachDB](https://quay.io/repository/phasetwo/keycloak-crdb?tab=info).

## Extensions

This distribution contains the following extensions:

| Component               | Status             | Repository                                                    | Description                                                                               |
| ----------------------- | ------------------ | ------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Admin Portal            | :white_check_mark: | https://github.com/p2-inc/phasetwo-admin-portal               | User self-management for their account and organizations.                                 |
| Admin UI                | :white_check_mark: | https://github.com/p2-inc/keycloak-themes                     | Admin UI customization are distributed through the phasetwo-ui theme.                     |
| Events                  | :white_check_mark: | https://github.com/p2-inc/keycloak-events                     | All event listener implementations.                                                       |
| IdP Wizards             | :white_check_mark: | https://github.com/p2-inc/idp-wizard                          | Identity Provider setup wizards for self-management of SSO admins and organizations.      |
| Magic Link              | :white_check_mark: | https://github.com/p2-inc/keycloak-magic-link                 | Magic Link Authentication. Created with an Authenticator or Resource.                     |
| Organizations           | :white_check_mark: | https://github.com/p2-inc/keycloak-orgs                       | Organizations multi-tenant entities, resources and APIs.                                  |
| Themes                  | :white_check_mark: | https://github.com/p2-inc/keycloak-themes                     | Login and email theme customizations via Realm attributes without deploying an extension. |
| User Migration          | :white_check_mark: | https://github.com/p2-inc/keycloak-user-migration             | User migration storage provider and API client.                                           |
| Apple Identity Provider | :white_check_mark: | https://github.com/klausbetz/apple-identity-provider-keycloak | Enables Sign in with Apple for web-based and native applications (via token-exchange)     |

## Differences

### Cache

This packages a `cache-ispn-jdbc-ping.xml` for setting up Infinispan/JGroups discovery via the `JDBC` ping protocol. To use it, set the environment variable `KC_CACHE_CONFIG_FILE: cache-ispn-jdbc-ping.xml`.

### CockroachDB

If you are using CockroachDB, for **Keycloak 26** there are changes:

- There is now a wrapper JDBC driver that is placed in the `/opt/keycloak/providers/` directory. If you are building a custom image based on this one, it must be copied to the target image.
- If you are using the `KC_DB_URL`, it now has the format `jdbc:cockroachdb://...` rather than `postgres`. This will also be important to configure if you're using JGroups JDBC_PING.
- You **must** use the `useCockroachMetadata=true` property in your `KC_DB_URL_PROPERTIES`

## Versioning

Format for version is `<keycloak-version>-<build-timestamp>` e.g. `24.0.4.1688664025`.

There will also be major/minor/patch version tags released. E.g.

- `26`
- `26.0`
- `26.0.2`
- `26.0.2.1688664025`

## Building

### Prerequisite: build Keycloak from source

The Keycloak versions this image tracks are tagged upstream but **not
published** — no jars on Maven Central, no image on quay.io. So Keycloak has
to be built from source before either `libs/` or the image can be built:

```bash
scripts/build-keycloak.sh            # version comes from libs/pom.xml
```

That builds `p2-inc/keycloak` branch `<version>_crdb` (the upstream tag plus
the CockroachDB patches), `mvn install`s the reactor into your `~/.m2`, and
stages a build context in `.keycloak-build/out`:

```
dist/keycloak-<version>.tar.gz      the server distribution (stage 2's base)
dist/cockroachdb-jdbc-driver-*.jar  CRDB driver, carried by the fork
m2/repository/org/keycloak/**       artifacts libs/ compiles against
```

The script is safe to re-run: it resolves the branch head with `git ls-remote`
and no-ops if that commit is already installed, so it costs a couple of
seconds on every build but the first. Pass a version explicitly
(`scripts/build-keycloak.sh 26.6.6`) to build something other than what
`libs/pom.xml` pins, and `--help` for the rest.

Everything it produces is architecture-independent (JVM-mode Quarkus), so one
build serves x86 and arm laptops as well as both `linux/amd64` and
`linux/arm64` image builds.

In CI this is the `.github/actions/keycloak-artifacts` composite action, which
wraps the same script in an `actions/cache` keyed on the CRDB branch head —
only a Keycloak version bump pays the build cost.

The script has its own test suite:

```bash
scripts/test-build-keycloak.sh        # ~8s; -v to dump output for failures
```

It runs the real script against a fake upstream git repository whose `mvnw` is
a stub, so branch resolution, cloning, fetching, staging, the stamp, the
cache-restore path, the JDK search and every error path are exercised in
seconds without a Keycloak build. It touches nothing outside a temp dir — not
your `~/.m2`, not `.keycloak-build/`. CI runs it on every PR.

#### Equivalence with the `keycloak-crdb` image

Stage 2 used to start `FROM quay.io/phasetwo/keycloak-crdb`, whose own
Dockerfile (`quarkus/container/Dockerfile` in the fork) does exactly four
things to the distribution: unpack the tarball to `/opt/keycloak`, create
`data/`, drop the CockroachDB JDBC driver into `providers/` as
`io.cockroachdb.jdbc.cockroachdb-jdbc-driver-<v>.jar`, and `chmod -R g+rwX`.
Stage 2 now performs the same four steps directly. Everything else in that
Dockerfile builds a UBI9-micro runtime (`ubi-null.sh`, the `1000:0` user, the
UBI package set) that this repo's Wolfi runtime stage has always discarded —
it only ever copied `/opt/keycloak` across.

That was verified by diffing a locally built 26.6.4 distribution against the
published `quay.io/phasetwo/keycloak-crdb:26.6.4` image:

- identical file sets (495 files), and the CRDB driver jar is byte-identical;
- 437 of 474 jars content-identical (per-entry CRC), the remainder being the
  35 locally rebuilt `org.keycloak.*` jars — where every `.class` entry is
  byte-identical and only `MANIFEST.MF` (builder OS, JDK patch level, SCM
  revision) and `keycloak-version.properties` (build timestamp) differ;
- all non-jar files byte-identical except three Quarkus classpath metadata
  files, which encode the brotli artifact name below and are regenerated by
  stage 2's `kc.sh build` anyway. No builder-local paths are embedded.

Two build-host sensitivities are worth knowing about:

**JDK.** Keycloak is built on JDK 21 and its jars record `Build-Jdk-Spec: 21`.
Building with a newer JDK succeeds but emits different bytecode, so the script
looks for a JDK 21 rather than trusting `JAVA_HOME` — version managers like
jenv point it at the newest install. Override with `KEYCLOAK_JAVA_HOME`.

**brotli4j native.** The distribution embeds one platform-specific jar,
`com.aayushatharva.brotli4j.native-*`, selected by OS-activated profiles in
brotli4j's own pom (so it cannot be overridden from the command line). CI
builds on Linux/x86_64 and therefore stages `native-linux-x86_64`, matching
every published image. A build on an arm Mac stages `native-osx-aarch64`
instead, so brotli compression is unavailable in locally built images —
harmless for local testing, and note the published arm64 images have always
carried the x86_64 native for the same reason.

### Building the image

The Maven build of the `libs/` project is performed inside the `Dockerfile`
itself, so a single `docker build` command produces the final image — no
host-side JDK or Maven install required. The Keycloak artifacts staged above
are passed in as a named build context:

```bash
docker buildx build --build-context keycloak=.keycloak-build/out \
    -t quay.io/phasetwo/phasetwo-keycloak:$VERSION .
```

or via compose, which defaults the context to `./.keycloak-build/out`:

```bash
docker compose build keycloak
```

If that context is missing or empty the build fails with a pointer back to
`scripts/build-keycloak.sh`, rather than silently resolving a different
Keycloak from Central.

The build uses three stages:

1. `libs-builder` — a `maven:3.9-eclipse-temurin-21` stage that runs
   `mvn clean package` against `libs/` to produce the bundled provider jars.
   It is pinned to `$BUILDPLATFORM` so multi-arch builds are not slowed by
   qemu emulation, and uses a BuildKit `--mount=type=cache` for `~/.m2`.
2. `keycloak-builder` — unpacks the source-built server distribution from
   the `keycloak` build context onto `eclipse-temurin:21-jdk`, adds the
   CockroachDB JDBC driver, copies the jars (from stage 1 and from
   `libs/ext/`) into `/opt/keycloak/providers/` and runs `kc.sh build` to
   pre-augment Quarkus. This previously started `FROM
   quay.io/phasetwo/keycloak-crdb`, which only works for versions that were
   actually imaged.
3. Final runtime — based on `cgr.dev/chainguard/wolfi-base`, carries only
   the augmented `/opt/keycloak` tree across from stage 2, installs an
   OpenJDK 21 JRE + bash + CA bundle, and runs as a non-root user. See
   the *Hardening* section below.

### Building against a local SNAPSHOT (`host-m2`)

If you are iterating on a Phase Two extension (`keycloak-orgs`,
`keycloak-themes`, etc.) and have installed a SNAPSHOT to your host
`~/.m2`, you can expose that repository to the in-Dockerfile Maven
build via the optional `host-m2` named build context. With no override,
the Dockerfile resolves `host-m2` to an inline empty `FROM scratch`
stage, so CI behavior is unchanged.

**With `docker build`:**

```bash
# Default — host-m2 is empty, everything comes from Maven Central
docker buildx build .

# Override — overlay your host's m2 repo onto the build cache
docker buildx build --build-context host-m2=$HOME/.m2 .
```

**With `docker compose`:** the compose file picks the override up from
the `HOST_M2` env var:

```bash
HOST_M2=$HOME/.m2 docker compose build keycloak
```

BuildKit transfers the entire `host-m2` context into its filesystem
before the build runs, so a large `~/.m2` (multiple GB) can be slow
and may exhaust Docker Desktop's disk. For faster iteration, stage
only the SNAPSHOTs you need:

```bash
mkdir -p /tmp/scoped-m2/repository/io/phasetwo/keycloak
cp -r ~/.m2/repository/io/phasetwo/keycloak/keycloak-orgs \
      /tmp/scoped-m2/repository/io/phasetwo/keycloak/

HOST_M2=/tmp/scoped-m2 docker compose build keycloak
# or:
docker buildx build --build-context host-m2=/tmp/scoped-m2 .
```

The Dockerfile uses `cp -rf` to overlay `host-m2` onto its m2 cache,
so a freshly-installed SNAPSHOT on the host always wins over a stale
copy in the BuildKit cache mount. Released artifacts are unaffected
because the overlay only contains what's in your staged directory.

## Local testing

```bash
docker compose build
docker compose up
```

This uses the local `docker-compose.yml` to rebuild the `keycloak` image and start the supporting services. When you are done, stop the stack with `docker compose down`.

The default compose stack starts `cockroach` and `keycloak` only. The `caddy` reverse proxy is now behind the `public-proxy` profile so local testing does not try to issue a public TLS certificate.

```bash
# optional reverse proxy for local HTTP testing
docker compose --profile public-proxy up

# optional public HTTPS endpoint
CADDY_FROM=https://your-hostname:443 docker compose --profile public-proxy up
```

`keycloak.version` in `libs/pom.xml` is the single source of truth for the
Keycloak version — the Dockerfile no longer pins a base image tag. After
bumping it, re-run `scripts/build-keycloak.sh` (it will detect the new version
and build it) before rebuilding the image. This requires a matching
`<version>_crdb` branch to exist in `p2-inc/keycloak`; the script fails with
the list of available branches if it does not.

## Distribution

```
# build and push for both platforms
scripts/build-keycloak.sh
docker buildx build --platform linux/amd64,linux/arm64 --build-context keycloak=.keycloak-build/out --tag quay.io/phasetwo/phasetwo-keycloak:latest --tag quay.io/phasetwo/phasetwo-keycloak:$VERSION --push .
```

The Keycloak artifacts are architecture-independent, so the same context
serves both platforms — no need to build Keycloak twice.

Check to see if there are updated jars:

```
cd libs/
mvn versions:display-dependency-updates
```

## Security

This section consolidates the *what*, the *how it's built*, and the
*how it's continuously scanned* — everything security-relevant in one
place.

### Image properties

- **Base: Chainguard Wolfi** (`cgr.dev/chainguard/wolfi-base:latest`).
  Minimal, daily-rebuilt distro with same-day CVE patching, glibc (no
  musl quirks for the JVM), and Sigstore-signed packages. The
  full-distro Keycloak base only appears in the intermediate builder
  stage and is dropped before the final image is assembled.
- **Three runtime packages only:** `openjdk-21-default-jvm` (JRE),
  `bash` (required by `kc.sh`), and `ca-certificates-bundle`. No
  package manager utilities (`apk`'s cache is wiped at the end of the
  install step), no `curl`/`wget`, no build tooling.
- **Non-root, least-privilege account.** A dedicated `keycloak`
  account is created with UID/GID 2000 (UIDs are overridable at build
  time via `--build-arg USER=… --build-arg UID=… --build-arg GID=…`).
  UID 2000 avoids the UID-1000 collision with default user accounts
  used by many host systems.
- **Strict file permissions.** After copying `/opt/keycloak` into
  place, a `find … -exec chmod` sweep normalises every directory to
  `755`, every file to `644`, restores `755` on `bin/*.sh`, and clears
  any setuid/setgid bits inherited from upstream layers.
- **JVM hardened via `JAVA_OPTS_APPEND`.** Upstream `kc.sh` (in the
  Keycloak base image) already bakes in `-XX:+ExitOnOutOfMemoryError`,
  the `MaxRAMPercentage / MinRAMPercentage / InitialRAMPercentage` heap
  triple, the `MetaspaceSize / MaxMetaspaceSize` bounds,
  `-XX:+UseG1GC`, `-Djava.security.egd=file:/dev/urandom`,
  `-Dfile.encoding=UTF-8`, and the Flight Recorder defaults, so we
  only append:
  - `-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp/heap.hprof`
    — capture diagnostics on OOM (requires a writable `/tmp`; see the
    Kubernetes pod spec below).
  - `-Djava.awt.headless=true` — avoid AWT init for headless workloads.
- **HTTPS-first defaults.** `KC_HTTP_ENABLED=false` ships in the
  image; cleartext on the pod is an explicit opt-in for callers that
  need it (local `docker-compose` already does this).
- **Health and metrics enabled by default** (`KC_HEALTH_ENABLED`,
  `KC_METRICS_ENABLED`) so Kubernetes can probe `/health/live` and
  `/health/ready` directly. No Dockerfile `HEALTHCHECK` is declared —
  kubelet ignores it and runs its own probes.

### Build pipeline (security properties)

`docker build .` produces the final image from a three-stage build (see
[Building](#building) for the operational view). The security-relevant
points:

1. **Stage 1 (`libs-builder`)** — runs `mvn clean package` with
   `--strict-checksums`, so a corrupted artifact from Maven Central
   fails the build rather than silently shipping. Uses a BuildKit
   `--mount=type=cache` for `~/.m2` to keep this layer fast without
   embedding the cache in the image.
2. **Stage 2 (`keycloak-builder`)** — runs `kc.sh build` to
   pre-augment Quarkus, so production deployments can launch with
   `start --optimized` (no augmentation at runtime, no JDK tools needed
   at boot).
3. **Stage 3 (final runtime)** — `FROM cgr.dev/chainguard/wolfi-base`.
   Carries **only** `/opt/keycloak` across from stage 2; Maven, the JDK
   compiler, source files, and the upstream Keycloak base image's
   surface area never make it into the published image.

### Kubernetes deployment

The image is built non-root, so the orchestrator should enforce the
same from the outside. Recommended pod spec:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 2000
  runAsGroup: 2000
  fsGroup: 2000
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
volumes:
  - name: tmp
    emptyDir: {}
volumeMounts:
  - name: tmp
    mountPath: /tmp
```

A writable `/tmp` is required because Quarkus uses it for classgen and
the JVM writes its heap dump there on OOM.

### Vulnerability scanning

CVE management is split across three GitHub Actions workflows. The
unifying idea is that the Wolfi base image is rebuilt daily upstream,
so **triggering a fresh release is itself the patch mechanism** for
OS-package CVEs — no in-place patch layer (Copa, etc.) is needed.

| Workflow | When | What it does | Gate? |
| --- | --- | --- | --- |
| `verify.yml` | every PR | builds the image, runs Trivy + OpenVEX, uploads report | non-gating by default (`exit-code: 0`); flip to `'1'` + branch protection for hard gating |
| `release.yml` | every push to `main`, plus `workflow_dispatch` from `security-scan.yml` | builds and pushes multi-arch, then scans the just-pushed `quay.io/...:<VERSION_TAG>` and uploads SARIF (for the GitHub Security tab) + JSON | non-gating record of what shipped |
| `security-scan.yml` | daily 06:17 UTC + `workflow_dispatch` | pulls `quay.io/phasetwo/phasetwo-keycloak:latest`, scans both `linux/amd64` and `linux/arm64` for OS-package CVEs, single-arch for library CVEs, all with OpenVEX applied | dispatches `release.yml` if any OS-package HIGH/CRITICAL CVE remains |

The daily-scan → dispatch loop works because the rebuild's `apk add`
resolves against the now-patched Wolfi repositories, so the freshly
published image goes out clean.

**Library CVEs are reported but do not trigger a rebuild.** A Wolfi
refresh can't fix CVEs in the bundled JARs — the fix path for those is
a `libs/pom.xml` dependency bump, which needs human review. The daily
scan still surfaces them in the job summary and uploaded artifact so
they don't get lost.

### Documenting false positives (OpenVEX)

When Trivy flags a CVE that does not apply to this image — e.g. a
version-string parsing bug in the scanner, or a vulnerability in a code
path that isn't reachable here — add an OpenVEX statement to
`openvex.json` at the repo root. All three workflows pass that file to
Trivy via `vex:` so documented FPs are filtered without blanket
`--ignore-unfixed` style suppressions.

```json
{
  "vulnerability": { "name": "CVE-2025-59250" },
  "products": [
    { "@id": "pkg:maven/com.microsoft.sqlserver/mssql-jdbc@13.2.1" }
  ],
  "status": "not_affected",
  "justification": "vulnerable_code_not_present",
  "impact_statement": "Version 13.2.1.jre11 is in use but Trivy incorrectly parses the version string. This version is patched and safe."
}
```

Allowed `justification` values per the OpenVEX v0.2.0 spec:
`component_not_present`, `vulnerable_code_not_present`,
`vulnerable_code_not_in_execute_path`,
`vulnerable_code_cannot_be_controlled_by_adversary`, or
`inline_mitigations_already_exist`. Always include an
`impact_statement` so auditors have a paper trail — every entry lands
through normal PR review.

## Testing

You can try it in ephemeral, development mode with:

```bash
docker run --name phasetwo_test --rm -p 8080:8080 \
    -e KEYCLOAK_ADMIN=admin -e KEYCLOAK_ADMIN_PASSWORD=admin -e KC_HTTP_RELATIVE_PATH=/auth \
    quay.io/phasetwo/phasetwo-keycloak:26.5.0 \
    start-dev --spi-email-template-provider=freemarker-plus-mustache --spi-email-template-freemarker-plus-mustache-enabled=true --spi-theme-cache-themes=false
```

## Releases

https://quay.io/repository/phasetwo/phasetwo-keycloak?tab=tags

## Stats collection

This image collects anonymous usage statistics by default via a single HTTP request on startup. This includes version/commit/timestamp and number of realms/clients/orgs/users/idps. In order to block this, set the env var `PHASETWO_ANALYTICS_DISABLED=true`.

---

All documentation, source code and other files in this repository are Copyright 2025 Phase Two, Inc.
