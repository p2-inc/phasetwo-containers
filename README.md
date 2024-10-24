> :rocket: **Try it for free** in the new Phase Two [keycloak managed service](https://phasetwo.io/?utm_source=github&utm_medium=readme&utm_campaign=phasetwo-containers). Go to [Phase Two](https://phasetwo.io/) for more information.

# Phase Two Keycloak Docker image

Builds the base Phase Two Keycloak Docker image that is used in the self-serve clusters (both for shared and dedicated). This is based on the a Keycloak image which differs from the mainline with added support for [Keycloak on CockroachDB](https://quay.io/repository/phasetwo/keycloak-crdb?tab=info).

## Extensions

This distribution contains the following extensions:

| Component | Status | Repository | Description |
| --- | --- | --- | --- |
| Admin Portal | :white_check_mark: | https://github.com/p2-inc/phasetwo-admin-portal | User self-management for their account and organizations. |
| Admin UI | :white_check_mark: | https://github.com/p2-inc/keycloak-ui | Admin UI customizations. |
| Events | :white_check_mark: | https://github.com/p2-inc/keycloak-events | All event listener implementations. |
| IdP Wizards | :white_check_mark: | https://github.com/p2-inc/idp-wizard | Identity Provider setup wizards for self-management of SSO admins and organizations. |
| Magic Link | :white_check_mark: | https://github.com/p2-inc/keycloak-magic-link | Magic Link Authentication. Created with an Authenticator or Resource. |
| Organizations | :white_check_mark: | https://github.com/p2-inc/keycloak-orgs | Organizations multi-tenant entities, resources and APIs. |
| Themes |  :white_check_mark: | https://github.com/p2-inc/keycloak-themes | Login and email theme customizations via Realm attributes without deploying an extension. |
| User Migration | :white_check_mark: | https://github.com/p2-inc/keycloak-user-migration | User migration storage provider and API client. |

## Differences

This packages a `cache-ispn-jdbc-ping.xml` for setting up Infinispan/JGroups discovery via the `JDBC` ping protocol. To use it, set the environment variable `KC_CACHE_CONFIG_FILE: cache-ispn-jdbc-ping.xml`.

Because you may want to use a different driver class, and the url string differs from that of Keycloak, we have added 2 variables:
```
KC_ISPN_DB_DRIVER   # default is 'org.postgresql.Driver'
KC_ISPN_DB_VENDOR   # default is 'postgresql'
```

## Versioning

Format for version is `<keycloak-version>-<build-timestamp>` e.g. `24.0.4.1688664025`.

There will also be major/minor/patch version tags released. E.g.
- `24`
- `24.0`
- `24.0.4`
- `24.0.4.1688664025`

## Building

This project uses a maven project in `libs/` to fetch all of the jars that will be included in the Docker image.

```
# build the libs project
cd libs/
mvn package
cd ..
# build the image for local testing
docker build -t quay.io/phasetwo/phasetwo-keycloak:$VERSION -f Dockerfile .
```

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

## Testing

You can try it in ephemeral, development mode with:

```
docker run --name phasetwo_test --rm -p 8080:8080 \
    -e KEYCLOAK_ADMIN=admin -e KEYCLOAK_ADMIN_PASSWORD=admin -e KC_HTTP_RELATIVE_PATH=/auth \
    quay.io/phasetwo/phasetwo-keycloak:$VERSION \
    start-dev --spi-email-template-provider=freemarker-plus-mustache --spi-email-template-freemarker-plus-mustache-enabled=true --spi-theme-cache-themes=false
```

There are docker compose examples for Postgres and Cockroach in the `examples/` directory. E.g.:

```
docker rmi -f phasetwo/phasetwo-keycloak-crdb:latest
docker build -t phasetwo/phasetwo-keycloak-crdb:latest -f examples/cockroach/Dockerfile .
# If you need to inspect the image contents, use:
docker run -it --rm  --entrypoint /bin/bash phasetwo/phasetwo-keycloak-crdb:latest
# Run it with a single-node crdb instance and caddy as a reverse proxy
docker-compose -f examples/cockroach/crdb-keycloak.yml up
```

## Releases

https://quay.io/repository/phasetwo/phasetwo-keycloak?tab=tags
