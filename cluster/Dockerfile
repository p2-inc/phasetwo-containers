FROM quay.io/phasetwo/phasetwo-keycloak:latest as builder

ENV KC_DB=cockroach
ENV KC_METRICS_ENABLED=true
ENV KC_HEALTH_ENABLED=true
ENV KC_FEATURES=preview,admin2
ENV KC_HTTP_RELATIVE_PATH=/auth
ENV KC_CACHE_CONFIG_FILE=cache-ispn-jdbc-ping.xml
ENV KC_TRANSACTION_XA_ENABLED=false
ENV KC_TRANSACTION_JTA_ENABLED=false

COPY ./conf/cache-ispn-jdbc-ping.xml /opt/keycloak/conf/cache-ispn-jdbc-ping.xml

COPY ./cluster/lib/*.jar /opt/keycloak/providers/

RUN /opt/keycloak/bin/kc.sh build --spi-email-template-provider=freemarker-plus-mustache --spi-email-template-freemarker-plus-mustache-enabled=true

FROM quay.io/phasetwo/phasetwo-keycloak:latest

COPY --from=builder /opt/keycloak/lib/quarkus/ /opt/keycloak/lib/quarkus/
COPY --from=builder /opt/keycloak/providers/ /opt/keycloak/providers/

ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "-v", "start", "--optimized --spi-email-template-provider=freemarker-plus-mustache --spi-email-template-freemarker-plus-mustache-enabled=true" ]
