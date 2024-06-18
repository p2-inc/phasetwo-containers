FROM quay.io/phasetwo/phasetwo-keycloak:latest as builder

ENV KC_DB=cockroach
ENV KC_METRICS_ENABLED=true
ENV KC_HEALTH_ENABLED=true
ENV KC_FEATURES=persistent-user-sessions,admin-fine-grained-authz,client-secret-rotation,dpop,passkeys,recovery-codes,scripts,token-exchange,update-email
ENV KC_HTTP_RELATIVE_PATH=/auth
ENV KC_CACHE_CONFIG_FILE=cache-ispn-jdbc-ping.xml

COPY cache-ispn-jdbc-ping.xml /opt/keycloak/conf/cache-ispn-jdbc-ping.xml
COPY p2-entrypoint.sh /opt/keycloak/bin/p2-entrypoint.sh

#COPY ./lib/*.jar /opt/keycloak/providers/

RUN /opt/keycloak/bin/kc.sh build --spi-email-template-provider=freemarker-plus-mustache --spi-email-template-freemarker-plus-mustache-enabled=true --spi-theme-cache-themes=false

FROM quay.io/phasetwo/phasetwo-keycloak:latest

COPY --from=builder /opt/keycloak/lib/quarkus/ /opt/keycloak/lib/quarkus/
COPY --from=builder /opt/keycloak/providers/ /opt/keycloak/providers/
COPY --from=builder /opt/keycloak/conf/cache-ispn-jdbc-ping.xml /opt/keycloak/conf/cache-ispn-jdbc-ping.xml
COPY --from=builder /opt/keycloak/bin/p2-entrypoint.sh /opt/keycloak/bin/p2-entrypoint.sh

ENTRYPOINT [ "/opt/keycloak/bin/p2-entrypoint.sh" ]
