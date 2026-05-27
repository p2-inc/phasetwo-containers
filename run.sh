#!/bin/bash

cd libs/ && mvn clean install && cd .. && docker compose build && docker compose up
