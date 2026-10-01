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

### 3rd Party

- rest-migration

## Libraries

- wildfly-client-config
- dnsjava

## Removed

### phasetwo-admin-ui

`libs/ext/phasetwo-admin-ui-<version>.jar` was a prebuilt fork of Keycloak's Admin
UI, registering the `phasetwo.v2` admin theme and overriding the built-in
`keycloak.v2`. **It is no longer included.**

The admin theme in [keycloak-themes](https://github.com/p2-inc/keycloak-themes)
supersedes it: that project builds the admin console from source as part of its
normal release, and ships it as the `phasetwo-ui` theme (which also covers
`account`, `email` and `login`).

The prebuilt jar was pinned to a Keycloak 26.4 base and had to be rebuilt by hand
for every server bump, so it drifted — by the 26.8.0 port it was four minors
behind the server it shipped with, leaving the console out of sync with the admin
REST API. Dropping it also restores Keycloak's own, version-matched `keycloak.v2`.

**Migration:** realms whose admin theme is set to `phasetwo.v2` must be changed to
`phasetwo-ui` (*Realm Settings* -> *Themes* -> *Admin theme*). A realm left on
`phasetwo.v2` falls back to the server default.

## Internal extensions

- version provider - prints a banner on startup, provides version information in the admin UI, collects anonymous usage stats
- mdc filter - adds the realm as an MDC logging property as a request filter

