> :rocket: **Try it for free** in the new Phase Two [keycloak managed service](https://phasetwo.io/dashboard/?utm_source=github&utm_medium=readme&utm_campaign=phasetwo-containers). See the [announcement and demo video](https://phasetwo.io/blog/self-service/) for more information.

# Phase Two Keycloak image

Contains the base Phase Two Keycloak image that is used in the self-serve clusters (both for shared and dedicated). This is based on the a Keycloak image which differs from the mainline only in that it supports CockroachDB for the legacy store type.

## Extensions

This distribution contains the following extensions:

| Component | Status | Repository | Description |
| --- | --- | --- | --- |
| Events | :white_check_mark: | https://github.com/p2-inc/keycloak-events | All event listener implementations. |
| User Migration | :white_check_mark: | https://github.com/p2-inc/keycloak-user-migration | User migration storage provider and API client. |
| Organizations | :white_check_mark: | https://github.com/p2-inc/keycloak-orgs | Organizations multi-tenant entities, resources and APIs. |
| Magic Link | :white_check_mark: | https://github.com/p2-inc/keycloak-magic-link | Magic Link Authentication. Created with an Authenticator or Resource. |
| Admin UI | :white_check_mark: | https://github.com/p2-inc/keycloak-ui | Admin UI customizations. |
| Themes |  :white_check_mark: | https://github.com/p2-inc/keycloak-themes | Login and email theme customizations via Realm attributes without deploying an extension. |

Also, the distribution contains the `keycloak-admin-client` and the dependencies required to run it in this version without Resteasy dependency hell.

## Versioning

Format for version is `<keycloak-version>-<phasetwo-minor-version>` e.g. `20.0.1-alpha`, `20.0.1-0`

## Building

```
# set the version number
export VERSION=20.0.1-alpha
# build the libs project
cd libs/
mvn install
cd ..
# remove the old image if necessary
docker rmi -f quay.io/phasetwo/phasetwo-keycloak:$VERSION
# build the image
docker build -t quay.io/phasetwo/phasetwo-keycloak:$VERSION -f Dockerfile .
```

## Distribution

```
docker push quay.io/phasetwo/phasetwo-keycloak:$VERSION
```

## Testing

You can try it in ephemeral development mode with:

```
docker run --name phasetwo_test --rm -p 8080:8080 \
    -e KEYCLOAK_ADMIN=admin -e KEYCLOAK_ADMIN_PASSWORD=admin -e KC_HTTP_RELATIVE_PATH=/auth \
    quay.io/phasetwo/phasetwo-keycloak:$VERSION \
    start-dev
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

- 19.0.1-alpha
- 19.0.3-alpha
- 20.0.0-alpha
- 20.0.1-alpha
