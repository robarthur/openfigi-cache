#!/bin/bash

set -e

# set workingdir to script location
cd "${0%/*}"

docker-compose -f ../../docker/docker-compose.yml up --force-recreate -d

aws dynamodb create-table \
    --table-name MappingsV3 \
    --attribute-definitions \
        AttributeName=id,AttributeType=S \
        AttributeName=figi,AttributeType=S \
    --key-schema \
        AttributeName=id,KeyType=HASH \
        AttributeName=figi,KeyType=RANGE \
    --billing-mode PROVISIONED \
    --provisioned-throughput ReadCapacityUnits=25,WriteCapacityUnits=25 \
    --endpoint-url http://localhost:8000

python-lambda-local -l ../../env/lib/ -f lambda_handler -t 5 -e ../env_variables.json ../src/main.py event.json
