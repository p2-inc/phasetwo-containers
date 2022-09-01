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
| Admin UI | :white_check_mark: | https://github.com/p2-inc/keycloak-admin-ui | Admin UI customizations. |
| Home IdP Discovery | :white_check_mark: | https://github.com/sventorben/keycloak-home-idp-discovery | Discover home identity provider or realm by email domain. |
| Login Theme | *Fall 2022* | | Customizable login theme. |

Also, the distribution contains the `keycloak-admin-client` and the dependencies required to run it in this version without Resteasy dependency hell.

## Versioning

Format for version is <keycloak-version>-<phasetwo-minor-version> e.g. 19.0.1-alpha, 19.0.1-0

## Building

```
#docker rmi -f quay.io/phasetwo/phasetwo-keycloak:latest
docker build -t quay.io/phasetwo/phasetwo-keycloak:latest -f Dockerfile .
```

## Distribution

```
docker push quay.io/phasetwo/phasetwo-keycloak:VERSION
```

## Testing

There are examples for Postgres and Cockroach in the `examples/` directory. E.g.:

```
cd examples/cockroach/
docker rmi -f phasetwo/phasetwo-keycloak-crdb:latest
docker build -t phasetwo/phasetwo-keycloak-crdb:latest -f Dockerfile .
# If you need to inspect the image contents, use:
docker run -it --rm  --entrypoint /bin/bash phasetwo/phasetwo-keycloak-crdb:latest
# Run it with a single-node crdb instance and caddy as a reverse proxy
docker-compose -f crdb-keycloak.yml up
```
