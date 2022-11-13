#!/bin/bash

VERSION=$1
[ -z "$VERSION" ] && exit 1;

echo building image for $VERSION

docker rmi -f quay.io/phasetwo/phasetwo-keycloak:$VERSION
docker build -t quay.io/phasetwo/phasetwo-keycloak:$VERSION -f Dockerfile .
docker push quay.io/phasetwo/phasetwo-keycloak:$VERSION
