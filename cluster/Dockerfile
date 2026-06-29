FROM quay.io/phasetwo/phasetwo-keycloak:latest AS builder

ENV KC_DB=cockroach
ENV KC_METRICS_ENABLED=true
ENV KC_HEALTH_ENABLED=true
ENV KC_FEATURES=client-secret-rotation,scripts,token-exchange
ENV KC_CACHE_CONFIG_FILE=cache-ispn-jdbc-ping.xml
ENV KC_SPI_EVENTS_STORE_PROVIDER=ext-event-mdc-logger-store
ENV KC_SPI_EVENTS_STORE_EXT_EVENT_MDC_LOGGER_STORE_USE_JPA=true
ENV EXT_EVENT_MDC_LOGGER_ENABLED=true

COPY cache-ispn-jdbc-ping.xml /opt/keycloak/conf/cache-ispn-jdbc-ping.xml

RUN /opt/keycloak/bin/kc.sh build --spi-email-template-provider=freemarker-plus-mustache --spi-email-template-freemarker-plus-mustache-enabled=true --spi-theme-cache-themes=false

FROM quay.io/phasetwo/phasetwo-keycloak:latest

ENV KC_SPI_EVENTS_STORE_PROVIDER=ext-event-mdc-logger-store
ENV KC_SPI_EVENTS_STORE_EXT_EVENT_MDC_LOGGER_STORE_USE_JPA=true
ENV EXT_EVENT_MDC_LOGGER_ENABLED=true

COPY --from=builder /opt/keycloak/lib/quarkus/ /opt/keycloak/lib/quarkus/
COPY --from=builder /opt/keycloak/providers/ /opt/keycloak/providers/
COPY --from=builder /opt/keycloak/conf/cache-ispn-jdbc-ping.xml /opt/keycloak/conf/cache-ispn-jdbc-ping.xml
