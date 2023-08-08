> :rocket: **Try it for free** in the new Phase Two [keycloak managed service](https://phasetwo.io/dashboard/?utm_source=github&utm_medium=readme&utm_campaign=phasetwo-containers). See the [announcement and demo video](https://phasetwo.io/blog/self-service/) for more information.

# Phase Two Keycloak image

Contains the base Phase Two Keycloak image that is used in the self-serve clusters (both for shared and dedicated). This is based on the a Keycloak image which differs from the mainline only in that it supports [Keycloak on CockroachDB](https://quay.io/repository/phasetwo/keycloak-crdb?tab=info) for the legacy store type.

## Extensions

This distribution contains the following extensions:

| Component | Status | Repository | Description |
| --- | --- | --- | --- |
| Events | :white_check_mark: | https://github.com/p2-inc/keycloak-events | All event listener implementations. |
| Magic Link | :white_check_mark: | https://github.com/p2-inc/keycloak-magic-link | Magic Link Authentication. Created with an Authenticator or Resource. |
| Organizations | :white_check_mark: | https://github.com/p2-inc/keycloak-orgs | Organizations multi-tenant entities, resources and APIs. |
| Themes |  :white_check_mark: | https://github.com/p2-inc/keycloak-themes | Login and email theme customizations via Realm attributes without deploying an extension. |
| Admin UI | :white_check_mark: | https://github.com/p2-inc/keycloak-ui | Admin UI customizations. |
| Admin Portal | :white_check_mark: | https://github.com/p2-inc/phasetwo-admin-portal | User self-management for their account and organizations. |
| User Migration | :white_check_mark: | https://github.com/p2-inc/keycloak-user-migration | User migration storage provider and API client. |

Also, the distribution contains the `keycloak-admin-client` and the dependencies required to run it in this version without Resteasy dependency hell.

## Differences

This packages a `cache-ispn-jdbc-ping.xml` for setting up Infinispan/JGroups discovery via the `JDBC` ping protocol. To use it, set the environment variable `KC_CACHE_CONFIG_FILE: cache-jdbc-persistent.xml`.

Because you may want to use a different driver class, and the url string differs from that of Keycloak, we have added 2 variables:
```
KC_ISPN_DB_DRIVER   # default is 'org.postgresql.Driver'
KC_ISPN_DB_VENDOR   # default is 'postgresql'
```

## Versioning

Format for version is `<keycloak-version>-<build-timestamp>` e.g. `21.1.2.1688664025`.

There will also be major/minor/patch version tags released. E.g.
- `21`
- `21.1`
- `21.1.2`
- `21.1.2.1688664025`

## Building

```
# build the libs project
cd libs/
mvn package
cd ..
# build the image
docker build -t quay.io/phasetwo/phasetwo-keycloak:$VERSION -f Dockerfile .
```

## Distribution

```
docker push quay.io/phasetwo/phasetwo-keycloak:$VERSION
```

## Testing

You can try it in ephemeral, development mode with:

```
docker run --name phasetwo_test --rm -p 8080:8080 \
    -e KEYCLOAK_ADMIN=admin -e KEYCLOAK_ADMIN_PASSWORD=admin -e KC_HTTP_RELATIVE_PATH=/auth \
    quay.io/phasetwo/phasetwo-keycloak:$VERSION \
    start-dev --spi-email-template-provider=freemarker-plus-mustache --spi-email-template-freemarker-plus-mustache-enabled=true --spi-theme-cache-themes=false
```

There are examples for Postgres and Cockroach in the `examples/` directory. E.g.:

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

## User-contributed docs

- [Installing in an unpacked Keycloak, using without docker](docs/manual-install.md) from @cato447
