#!/usr/bin/env bash

tool="{{tool}}"
execdir="$PWD"

pushd $BUILD_WORKING_DIRECTORY > /dev/null
"$execdir/$tool" "$@"
popd > /dev/null
