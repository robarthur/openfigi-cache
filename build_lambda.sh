#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"

rm -rf deploy/*

deploy_packages="keys mappings"

pip install -r ./requirements.txt -t deploy/lib/ --upgrade

for package in ${deploy_packages}; do
  echo "Building $package"
  mkdir -p deploy/${package}_source/
  cp python/src/${package}.py deploy/${package}_source/
  cp -r deploy/lib/* deploy/${package}_source/
  cd deploy/${package}_source/ && zip -r ../${package}.zip * && cd -
done