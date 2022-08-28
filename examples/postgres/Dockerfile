FROM quay.io/phasetwo/phasetwo-keycloak:latest as builder

ENV KC_DB=postgres
ENV KC_HTTP_RELATIVE_PATH=/auth
ENV KC_CACHE_CONFIG_FILE=cache-ispn-jdbc-ping.xml

COPY ./../../conf/cache-ispn-jdbc-ping.xml /opt/keycloak/conf/cache-ispn-jdbc-ping.xml

RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/phasetwo/phasetwo-keycloak:latest

COPY --from=builder /opt/keycloak/lib/quarkus/ /opt/keycloak/lib/quarkus/
COPY --from=builder /opt/keycloak/providers/ /opt/keycloak/providers/

ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "-v", "start", "--optimized" ]
