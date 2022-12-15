#!/bin/bash

VERSION=$1
[ -z "$VERSION" ] && exit 1;

echo building image for $VERSION

cd libs/
mvn clean install
cd ../
docker rmi -f quay.io/phasetwo/phasetwo-keycloak:$VERSION
docker build -t quay.io/phasetwo/phasetwo-keycloak:$VERSION -f Dockerfile .

echo "# push to quay (must be logged in)"
echo "docker push quay.io/phasetwo/phasetwo-keycloak:$VERSION"

echo "# inspect container"
echo "docker run -it --rm  --entrypoint /bin/bash quay.io/phasetwo/phasetwo-keycloak:$VERSION"

echo "# run dev version"
echo "docker run --name phasetwo_test --rm -p 8080:8080 -e KEYCLOAK_ADMIN=admin -e KEYCLOAK_ADMIN_PASSWORD=admin -e KC_HTTP_RELATIVE_PATH=/auth quay.io/phasetwo/phasetwo-keycloak:$VERSION start-dev --spi-email-template-provider=freemarker-plus-mustache --spi-email-template-freemarker-plus-mustache-enabled=true"
