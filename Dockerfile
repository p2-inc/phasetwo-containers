FROM quay.io/phasetwo/keycloak-crdb:20.0.1 as builder

ENV KC_METRICS_ENABLED=true
ENV KC_HEALTH_ENABLED=true
ENV KC_FEATURES=preview
#ENV KC_DB=postgres
#ENV KC_HTTP_RELATIVE_PATH=/auth
#ENV KC_CACHE_CONFIG_FILE=cache-ispn-jdbc-ping.xml

# jdbc_ping infinispan configuration
#COPY ./conf/cache-ispn-jdbc-ping.xml /opt/keycloak/conf/cache-ispn-jdbc-ping.xml

# custom keycloak.conf
#COPY ./conf/keycloak.conf /opt/keycloak/conf/keycloak.conf

# 3rd party themes and extensions
COPY ./lib/*.jar /opt/keycloak/providers/

RUN /opt/keycloak/bin/kc.sh --verbose build

FROM quay.io/phasetwo/keycloak-crdb:20.0.1

COPY --from=builder /opt/keycloak/lib/quarkus/ /opt/keycloak/lib/quarkus/
COPY --from=builder /opt/keycloak/providers/ /opt/keycloak/providers/

WORKDIR /opt/keycloak
# this cert shouldn't be used, as it's just to stop the startup from complaining
RUN keytool -genkeypair -storepass password -storetype PKCS12 -keyalg RSA -keysize 2048 -dname "CN=server" -alias server -ext "SAN:c=DNS:localhost,IP:127.0.0.1" -keystore conf/server.keystore

#ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "-v", "start", "--optimized" ]
#ENTRYPOINT [ "/opt/keycloak/bin/kc.sh" ]
