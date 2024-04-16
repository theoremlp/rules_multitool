#!/usr/bin/env bash

tool="{{tool}}"
execdir="$PWD"

cd "$BUILD_WORKING_DIRECTORY" && exec "$execdir/$tool" "$@"
