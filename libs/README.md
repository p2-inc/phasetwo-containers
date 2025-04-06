# phasetwo-containers lib

This maven project has two functions:
1. collect all of the extensions and libraries that will be installed in the `/provider` dir of the image
2. include some extensions that are specific to the image, and do not have utility outside of that

## Extensions

### Phase Two

- keycloak-events
- keycloak-magic-link
- keycloak-orgs
- keycloak-themes
- phasetwo-admin-portal
- phasetwo-idp-wizard
- phasetwo-admin-ui

### 3rd Party

- rest-migration

## Libraries

- wildfly-client-config
- dnsjava

## Internal extensions

- version provider - prints a banner on startup, provides version information in the admin UI, collects anonymous usage stats
- mdc filter - adds the realm as an MDC logging property as a request filter

