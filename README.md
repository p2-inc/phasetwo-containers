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

Because you may want to use a different driver class, and the url string differs from that of Keycloak, we have added 2 variables:

```
KC_ISPN_DB_DRIVER   # default is 'org.postgresql.Driver'
KC_ISPN_DB_VENDOR   # default is 'postgresql'
```

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

## Hardening

The runtime image follows the practices in
<https://keymate.io/blog/hardened-keycloak-container-image>:

- **Chainguard Wolfi base.** The runtime image is built `FROM
  cgr.dev/chainguard/wolfi-base:latest` — a minimal, daily-rebuilt distro
  with same-day CVE patching, glibc (no musl quirks for the JVM), and
  Sigstore-signed packages. The full-distro Keycloak base is only used in
  the intermediate builder stage.
- **Minimal runtime package set.** Only three packages are installed on
  top of Wolfi: `openjdk-21-default-jvm` (JRE), `bash` (for `kc.sh`), and
  `ca-certificates-bundle`. No package manager utilities, no `curl`, no
  build tooling in the final layer.
- **Multi-stage build.** Maven, the JDK compiler, and source files live
  in builder stages only — the final image carries just `/opt/keycloak`.
- **Non-root execution and least privilege.** A dedicated `keycloak`
  account (UID/GID 2000, overridable at build time via
  `--build-arg USER=… UID=… GID=…`) is created in the Wolfi layer;
  `/opt/keycloak` is copied with `--chown=keycloak:keycloak`, then a
  `find … -exec chmod` sweep normalises permissions to **755 for
  directories, 644 for files, 755 for `bin/*.sh`**, also clearing any
  setuid/setgid bits inherited from upstream layers.
- **Build-time Quarkus augmentation.** `kc.sh build` runs at image build
  time so production deployments can launch with `start --optimized` and
  skip augmentation on every boot.
- **JVM hardening via `JAVA_OPTS_APPEND`:**
  `-XX:+ExitOnOutOfMemoryError`, `-XX:+HeapDumpOnOutOfMemoryError`,
  `-XX:MaxRAMPercentage=70`, `-XX:InitialRAMPercentage=50`, bounded
  metaspace, non-blocking entropy (`-Djava.security.egd=file:/dev/urandom`),
  and `-Djava.awt.headless=true`.
- **HTTPS-first defaults.** `KC_HTTP_ENABLED=false` ships in the image;
  deployments that need cleartext on the pod (local docker-compose,
  ingress-terminated TLS with HTTP upstream) opt in explicitly.
- **Health/metrics on by default** (`KC_HEALTH_ENABLED`,
  `KC_METRICS_ENABLED`) so orchestrators can use `/health/live` and
  `/health/ready` directly. No Dockerfile `HEALTHCHECK` is declared —
  Kubernetes ignores it; kubelet runs its own probes.
- **Strict Maven checksums.** The libs build runs with
  `--strict-checksums` so a corrupted artifact in transit fails the build
  rather than silently shipping.
- **No build tooling in the final layer.** Maven, the JDK compiler, and
  source trees are confined to the builder stages and never copied into
  the runtime image.

When running under Kubernetes you should additionally set on the pod
spec:

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
