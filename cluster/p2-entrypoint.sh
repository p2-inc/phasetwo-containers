#!/bin/bash

# Wrapper script as docker entrypoint

cp /foo/*.jar /opt/keycloak/providers/

if [ -d "/custom" ]; then
  cp -n /custom/*.jar /opt/keycloak/providers/
fi

# run the keycloak entrypoint with the given params
RUN_OPTS="$@"
/opt/keycloak/bin/kc.sh $RUN_OPTS
