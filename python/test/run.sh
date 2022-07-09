#!/bin/bash

# set workingdir to script location
cd "${0%/*}"

python-lambda-local -l ../../env/lib/ -f lambda_handler -t 5 -e ../env_variables.json ../src/main.py event.json
