FROM docker.io/phasetwo/cache-experiment:latest as builder

ENV KC_METRICS_ENABLED=true
ENV KC_HEALTH_ENABLED=true
ENV KC_TRANSACTION_XA_ENABLED=false
ENV KC_TRANSACTION_JTA_ENABLED=false
ENV KC_DB=cockroach
ENV KC_HTTP_RELATIVE_PATH=/auth
ENV KC_FEATURES=preview
ENV KC_CACHE_CONFIG_FILE=cache-kryo.xml
ENV KC_HOSTNAME_STRICT=false
ENV KC_HTTP_ENABLED=true
ENV KC_PROXY=edge
ENV KC_LOG_LEVEL=INFO

# jdbc_ping infinispan configuration
COPY ./cache-kryo.xml /opt/keycloak/conf/cache-kryo.xml

# 3rd party themes and extensions
#COPY ./*.jar /opt/keycloak/providers/
#COPY ./target/container*/*.jar /opt/keycloak/providers/

RUN /opt/keycloak/bin/kc.sh --verbose build 

FROM docker.io/phasetwo/cache-experiment:latest

USER 1000

COPY --from=builder /opt/keycloak/lib/quarkus/ /opt/keycloak/lib/quarkus/
COPY --from=builder /opt/keycloak/providers/ /opt/keycloak/providers/
COPY --from=builder /opt/keycloak/conf/cache-kryo.xml /opt/keycloak/conf/cache-kryo.xml

WORKDIR /opt/keycloak
# this cert shouldn'gt be used, as it's just to stop the startup from complaining
RUN keytool -genkeypair -storepass password -storetype PKCS12 -keyalg RSA -keysize 2048 -dname "CN=server" -alias server -ext "SAN:c=DNS:localhost,IP:127.0.0.1" -keystore conf/server.keystore

ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "--verbose", "start", "--optimized" ]
