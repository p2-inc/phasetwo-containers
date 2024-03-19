#!/bin/bash

# Wrapper script as docker entrypoint. Copies jar files from /custom to /opt/keycloak/providers/
# providing a facility to mount a directory and copy customer themes/extensions to the providers
# dir for loading at startup

if [ -d "/custom" ]; then
    for filename in /custom/*.jar; do
	fname=$(basename ${filename})
	if [ -f /opt/keycloak/providers/$fname ]; then
	    echo "WARNING: $fname already exists. OVERWRITING!"
	fi
	echo "Copying /custom/$fname to /opt/keycloak/providers/$fname"
	cp -n /custom/$fname /opt/keycloak/providers/$fname
    done
fi

# run the keycloak entrypoint with the given params
RUN_OPTS="$@"
echo "Running Keycloak with kc.sh $RUN_OPTS"
/opt/keycloak/bin/kc.sh $RUN_OPTS
