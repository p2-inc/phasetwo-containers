FROM quay.io/phasetwo/keycloak-crdb:26.6.2 AS builder

ENV KC_METRICS_ENABLED=true
ENV KC_HEALTH_ENABLED=true
ENV KC_FEATURES=preview

COPY ./conf/cache-ispn-jdbc-ping.xml /opt/keycloak/conf/cache-ispn-jdbc-ping.xml

# 3rd party themes and extensions
COPY ./libs/ext/*.jar /opt/keycloak/providers/
COPY ./libs/bundle/target/bundle*/*.jar /opt/keycloak/providers/

RUN /opt/keycloak/bin/kc.sh --verbose build --spi-email-template-provider=freemarker-plus-mustache --spi-email-template-freemarker-plus-mustache-enabled=true --spi-theme-cache-themes=false

FROM quay.io/phasetwo/keycloak-crdb:26.6.2

USER 1000

COPY --from=builder /opt/keycloak/lib/quarkus/ /opt/keycloak/lib/quarkus/
COPY --from=builder /opt/keycloak/providers/ /opt/keycloak/providers/
COPY --from=builder /opt/keycloak/conf/cache-ispn-jdbc-ping.xml /opt/keycloak/conf/cache-ispn-jdbc-ping.xml

WORKDIR /opt/keycloak

