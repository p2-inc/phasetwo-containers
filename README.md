> :rocket: **Try it for free** in the Phase Two [keycloak managed service](https://phasetwo.io/?utm_source=github&utm_medium=readme&utm_campaign=phasetwo-containers). Go to [Phase Two](https://phasetwo.io/) for more information.

# Phase Two Keycloak Docker image

Builds the base Phase Two Keycloak Docker image that is used in the self-serve clusters (both for shared and dedicated). This is based on the a Keycloak image which differs from the mainline with added support for [Keycloak on CockroachDB](https://quay.io/repository/phasetwo/keycloak-crdb?tab=info).

## Extensions

This distribution contains the following extensions:

| Component      | Status             | Repository                                        | Description                                                                               |
| -------------- | ------------------ | ------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Admin Portal   | :white_check_mark: | https://github.com/p2-inc/phasetwo-admin-portal   | User self-management for their account and organizations.                                 |
| Admin UI       | :white_check_mark: | https://github.com/p2-inc/keycloak                | Admin UI customizations.                                                                  |
| Events         | :white_check_mark: | https://github.com/p2-inc/keycloak-events         | All event listener implementations.                                                       |
| IdP Wizards    | :white_check_mark: | https://github.com/p2-inc/idp-wizard              | Identity Provider setup wizards for self-management of SSO admins and organizations.      |
| Magic Link     | :white_check_mark: | https://github.com/p2-inc/keycloak-magic-link     | Magic Link Authentication. Created with an Authenticator or Resource.                     |
| Organizations  | :white_check_mark: | https://github.com/p2-inc/keycloak-orgs           | Organizations multi-tenant entities, resources and APIs.                                  |
| Themes         | :white_check_mark: | https://github.com/p2-inc/keycloak-themes         | Login and email theme customizations via Realm attributes without deploying an extension. |
| User Migration | :white_check_mark: | https://github.com/p2-inc/keycloak-user-migration | User migration storage provider and API client.                                           |

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

This project uses a maven project in `libs/` to fetch all of the jars that will be included in the Docker image.

```bash
# build the libs project
cd libs/
mvn clean package
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

```bash
docker run --name phasetwo_test --rm -p 8080:8080 \
    -e KEYCLOAK_ADMIN=admin -e KEYCLOAK_ADMIN_PASSWORD=admin -e KC_HTTP_RELATIVE_PATH=/auth \
    quay.io/phasetwo/phasetwo-keycloak:$VERSION \
    start-dev --spi-email-template-provider=freemarker-plus-mustache --spi-email-template-freemarker-plus-mustache-enabled=true --spi-theme-cache-themes=false
```

## Releases

https://quay.io/repository/phasetwo/phasetwo-keycloak?tab=tags

## Stats collection

This image collects anonymous usage statistics by default via a single HTTP request on startup. This includes version/commit/timestamp and number of realms/clients/orgs/users/idps. In order to block this, set the env var `PHASETWO_ANALYTICS_DISABLED=true`.

---

All documentation, source code and other files in this repository are Copyright 2025 Phase Two, Inc.
