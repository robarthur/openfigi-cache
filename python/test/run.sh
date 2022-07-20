#!/bin/bash

set -e

# set workingdir to script location
cd "${0%/*}"
docker-compose -f ../../docker/docker-compose.yml up --force-recreate -t 3 -d
python-lambda-local -l ../../env/lib/ -f lambda_handler -t 5 -e ../env_variables.json ../src/mappings.py event.json
