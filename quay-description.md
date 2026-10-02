> **Try it for free** in the new [Phase Two](https://phasetwo.io/) [Keycloak managed service](https://phasetwo.io/?utm_source=quay&utm_medium=readme&utm_campaign=phasetwo-keycloak). See the [announcement and demo video](https://phasetwo.io/blog/self-service/) for more information.

# Phase Two enhanced Keycloak image

A drop-in replacement for the official Keycloak image, bundling the Phase Two extensions and a hardened runtime. This is the same image that backs the Phase Two self-serve clusters, shared and dedicated.

Keycloak itself is built from source from [`p2-inc/keycloak`](https://github.com/p2-inc/keycloak), which differs from mainline only in adding CockroachDB support for the legacy store type. The CockroachDB JDBC driver ships in the image.

Source and issues: [`p2-inc/phasetwo-containers`](https://github.com/p2-inc/phasetwo-containers).

## Versioning

Format is `<keycloak-version>.<build-timestamp>`, e.g. `26.8.0.1790855979`.

Rolling tags are also published, each pointing at the newest build on that line:

- `latest` — newest build of any version
- `26` — newest `26.x.y`
- `26.8` — newest `26.8.y`
- `26.8.0` — newest build of Keycloak 26.8.0

Pin `<keycloak-version>.<build-timestamp>` for reproducible deployments.

## Extensions

- **[Organizations](https://github.com/p2-inc/keycloak-orgs)** — multi-tenant organization entities, resources and APIs
- **[Themes](https://github.com/p2-inc/keycloak-themes)** — login, email and admin theme customization via realm attributes, with no extension deploy. Ships the `phasetwo-ui` theme
- **[Events](https://github.com/p2-inc/keycloak-events)** — event listener implementations, including webhooks
- **[Magic Link](https://github.com/p2-inc/keycloak-magic-link)** — magic-link authentication, as an authenticator or a REST resource
- **[Atomic Auth Flows](https://github.com/p2-inc/keycloak-atomic-auth-flows)** — create and modify authentication flows in a single API call
- **[SCIM Server](https://github.com/p2-inc/keycloak-scim-server)** — SCIM 2.0 user and group provisioning
- **[Admin Portal](https://github.com/p2-inc/phasetwo-admin-portal)** — self-management UI for users' accounts and organizations
- **[IdP Wizards](https://github.com/p2-inc/idp-wizard)** — guided identity-provider setup for SSO admins and organization owners
- **[User Migration](https://github.com/p2-inc/keycloak-user-migration)** — user migration storage provider and API client
- **[Apple Identity Provider](https://github.com/klausbetz/apple-identity-provider-keycloak)** — Sign in with Apple

### Admin console theme

Admin console customizations ship as the **`phasetwo-ui`** theme in [keycloak-themes](https://github.com/p2-inc/keycloak-themes), which also covers the `account`, `email` and `login` types.

> **Upgrading from an image before 26.8.0:** the prebuilt `phasetwo-admin-ui` jar, which registered a `phasetwo.v2` admin theme, has been removed — it had to be rebuilt by hand for each Keycloak release and had drifted behind the server. Realms with their admin theme set to `phasetwo.v2` must be changed to `phasetwo-ui` under *Realm Settings → Themes*, or they will fall back to the server default.

## Runtime

- Built on [Chainguard Wolfi](https://github.com/wolfi-dev), with only a JRE, `bash` and a CA bundle installed
- Runs as a non-root user (uid/gid `2000`)
- OpenJDK 21
- `linux/amd64` and `linux/arm64`
- A CycloneDX SBOM and SLSA provenance are attached to every published image

Retrieve the SBOM with:

```bash
docker buildx imagetools inspect --format '{{ json .SBOM }}' quay.io/phasetwo/phasetwo-keycloak:latest
```

### Defaults that differ from upstream

- **`KC_HEALTH_ENABLED=true`** — `/health/live` and `/health/ready` on port 9000, for Kubernetes probes
- **`KC_METRICS_ENABLED=true`** — Prometheus metrics on port 9000
- **`KC_HTTP_ENABLED=false`** — plaintext HTTP is off. Set it to `true` for local testing, or where TLS terminates in a sidecar

Ports exposed: `8080` (HTTP), `8443` (HTTPS), `9000` (health and metrics).

## Try it

Ephemeral development mode, no database required:

```bash
docker run --name phasetwo_test --rm -p 8080:8080 \
    -e KC_BOOTSTRAP_ADMIN_USERNAME=admin \
    -e KC_BOOTSTRAP_ADMIN_PASSWORD=admin \
    -e KC_HTTP_RELATIVE_PATH=/auth \
    quay.io/phasetwo/phasetwo-keycloak:latest \
    start-dev \
    --spi-email-template-provider=freemarker-plus-mustache \
    --spi-email-template-freemarker-plus-mustache-enabled=true \
    --spi-theme-cache-themes=false
```

Then open <http://localhost:8080/auth/> and sign in as `admin` / `admin`.

> On Keycloak 26 the admin bootstrap variables are `KC_BOOTSTRAP_ADMIN_USERNAME` and `KC_BOOTSTRAP_ADMIN_PASSWORD`. The older `KEYCLOAK_ADMIN` and `KEYCLOAK_ADMIN_PASSWORD` still work but log a deprecation warning.

Check the organizations API is live:

```bash
TOKEN=$(curl -s -X POST http://localhost:8080/auth/realms/master/protocol/openid-connect/token \
  -d client_id=admin-cli -d username=admin -d password=admin -d grant_type=password \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')

curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/auth/realms/master/orgs
```

## License

The Phase Two extensions are released under the [Elastic License 2.0](https://www.elastic.co/licensing/elastic-license). Keycloak itself remains Apache 2.0.
