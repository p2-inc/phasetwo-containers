#!/bin/bash

VERSION=$1
[ -z "$VERSION" ] && exit 1;

echo Building image for $VERSION

function checkout_build {
    echo "Building $1"
    git clone git@github.com:p2-inc/$1.git
    cd $1
    git checkout main && git rev-parse HEAD
    mvn -B clean package
    cp target/$1*.jar ../lib/
    cd ../
    rm -rf $1
}

checkout_build "idp-wizard"
checkout_build "admin-portal"

cp ../conf/cache-ispn-jdbc-ping.xml .

TAG_VERSION=$VERSION.$(date +%s)
echo Building the Docker image quay.io/phasetwo/phasetwo-cluster:$TAG_VERSION...
docker buildx build --platform linux/amd64,linux/arm64 --tag quay.io/phasetwo/phasetwo-cluster:latest --tag quay.io/phasetwo/phasetwo-cluster:$TAG_VERSION --file Dockerfile_nodb --push .

rm cache-ispn-jdbc-ping.xml
rm lib/*.jar
