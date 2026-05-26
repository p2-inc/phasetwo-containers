> :rocket: **Try it for free** in the Phase Two [keycloak managed service](https://phasetwo.io/?utm_source=github&utm_medium=readme&utm_campaign=phasetwo-containers). Go to [Phase Two](https://phasetwo.io/) for more information.

# Phase Two Keycloak Docker image

Builds the base Phase Two Keycloak Docker image that is used in the self-serve clusters (both for shared and dedicated). This is based on the a Keycloak image which differs from the mainline with added support for [Keycloak on CockroachDB](https://quay.io/repository/phasetwo/keycloak-crdb?tab=info).

## Extensions

This distribution contains the following extensions:

| Component               | Status             | Repository                                                    | Description                                                                               |
| ----------------------- | ------------------ | ------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Admin Portal            | :white_check_mark: | https://github.com/p2-inc/phasetwo-admin-portal               | User self-management for their account and organizations.                                 |
| Admin UI                | :white_check_mark: | https://github.com/p2-inc/keycloak                            | Admin UI customizations.                                                                  |
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

The Maven build of the `libs/` project is performed inside the `Dockerfile`
itself, so a single `docker build` command produces the final image — no
host-side JDK or Maven install required.

```bash
docker build -t quay.io/phasetwo/phasetwo-keycloak:$VERSION .
```

The build uses three stages:

1. `libs-builder` — a `maven:3.9-eclipse-temurin-21` stage that runs
   `mvn clean package` against `libs/` to produce the bundled provider jars.
   It is pinned to `$BUILDPLATFORM` so multi-arch builds are not slowed by
   qemu emulation, and uses a BuildKit `--mount=type=cache` for `~/.m2`.
2. `keycloak-builder` — based on `quay.io/phasetwo/keycloak-crdb`, copies
   the jars (from stage 1 and from `libs/ext/`) into
   `/opt/keycloak/providers/` and runs `kc.sh build` to pre-augment
   Quarkus.
3. Final runtime — based on `cgr.dev/chainguard/wolfi-base`, carries only
   the augmented `/opt/keycloak` tree across from stage 2, installs an
   OpenJDK 21 JRE + bash + CA bundle, and runs as a non-root user. See
   the *Hardening* section below.

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

If you are bumping `keycloak.version`, also update the base image tag in the `FROM quay.io/phasetwo/keycloak-crdb:...` lines in the `Dockerfile`. Otherwise the local image will still be built from the old Keycloak base image.

## Distribution

```
# build and push for both platforms
docker buildx build --platform linux/amd64,linux/arm64 --tag quay.io/phasetwo/phasetwo-keycloak:latest --tag quay.io/phasetwo/phasetwo-keycloak:$VERSION --push .
```

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
- **JVM hardened via `JAVA_OPTS_APPEND`:**
  - `-XX:+ExitOnOutOfMemoryError` — terminate cleanly on OOM rather
    than run degraded.
  - `-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp/heap.hprof`
    — capture diagnostics before exit.
  - `-XX:MaxRAMPercentage=70 -XX:InitialRAMPercentage=50` — bound the
    heap to container memory; the remaining 30 % covers native memory
    and metaspace.
  - `-XX:MetaspaceSize=96M -XX:MaxMetaspaceSize=256m` — bound
    metaspace to prevent classloader leaks.
  - `-Djava.security.egd=file:/dev/urandom` — non-blocking entropy so
    startup never stalls on `/dev/random`.
  - `-Djava.awt.headless=true` and `-Dfile.encoding=UTF-8`.
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
