FROM quay.io/phasetwo/phasetwo-keycloak:latest as builder

ENV KC_METRICS_ENABLED=true
ENV KC_HEALTH_ENABLED=true
ENV KC_FEATURES=preview,admin2
ENV KC_HTTP_RELATIVE_PATH=/auth
ENV KC_CACHE_CONFIG_FILE=cache-ispn-jdbc-ping.xml

COPY cache-ispn-jdbc-ping.xml /opt/keycloak/conf/cache-ispn-jdbc-ping.xml

COPY ./lib/*.jar /opt/keycloak/providers/

RUN /opt/keycloak/bin/kc.sh build --spi-email-template-provider=freemarker-plus-mustache --spi-email-template-freemarker-plus-mustache-enabled=true --spi-theme-cache-themes=false

FROM quay.io/phasetwo/phasetwo-keycloak:latest

COPY --from=builder /opt/keycloak/lib/quarkus/ /opt/keycloak/lib/quarkus/
COPY --from=builder /opt/keycloak/providers/ /opt/keycloak/providers/
COPY --from=builder /opt/keycloak/conf/cache-ispn-jdbc-ping.xml /opt/keycloak/conf/cache-ispn-jdbc-ping.xml
