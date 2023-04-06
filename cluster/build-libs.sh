#!/bin/bash

function checkout_build {
    echo "Building $1"
    GIT_SSH_COMMAND="ssh -v" git clone --verbose git@github.com:p2-inc/$1.git
    cd $1
    git checkout main && git rev-parse HEAD
    mvn -B clean package
    cp target/$1*.jar ../lib/
    cd ../
    rm -rf $1
}

checkout_build $1

