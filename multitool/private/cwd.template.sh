#!/usr/bin/env bash

tool="$PWD/{{tool}}"
cd "$BUILD_WORKING_DIRECTORY" && exec "$tool" "$@"
