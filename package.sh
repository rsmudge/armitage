#!/bin/bash

set -ex

./gradlew assemble


for i in unix windows mac; do

  if [ "${i}" == "mac" ] && [ "$(uname)" != "Darwin" ]; then
    echo "Skipping macOS build because this is not running on Darwin"
    continue
  fi

  mkdir -p "release/${i}"
  cp *.txt "release/${i}"
  cp build/*.jar "release/${i}"
  cp -r "dist/${i}/"* "release/${i}"

  if [ "${i}" == "mac" ] && [ "$(uname)" == "Darwin" ]; then
    pushd "release/${i}"
    ./build.sh
    popd
  fi

done;
