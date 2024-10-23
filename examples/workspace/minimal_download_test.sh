#!/usr/bin/env bash

set -o errexit -o pipefail -o nounset

# Determine a single file we are supposed to download for the host platform
OS="$(uname | tr '[:upper:]' '[:lower:]')"
ARCH="$(arch)"
ALLOWED="target-determinator.${OS}.${ARCH}"
if [ "$ARCH" == "x86_64" ]; then
    ALLOWED="target-determinator.${OS}.amd64"
fi

#############
# Test bzlmod
OUTPUT_BASE=$(mktemp -d)
REPO_CACHE=$(mktemp -d)
DL_CONFIG=$(mktemp)

# Construct a Bazel downloader config that forbids access to non-allowed files from multitool.lock.json
for file in target-determinator.darwin.arm64 target-determinator.linux.amd64 target-determinator.darwin.amd64; do
  if [ "$file" != "$ALLOWED" ]; then
    cat >$DL_CONFIG <<EOF
rewrite github.com/bazel-contrib/target-determinator/releases/download/([^/]+)/$file disallowed.build/\$1/$file
rewrite github.com/google/go-jsonnet/releases/download/(.*) disallowed.build/\$1
EOF
  fi
done

# This build will fail if we attempt a disallowed download
bazel "--output_base=$OUTPUT_BASE" build \
  --enable_bzlmod \
  "--repository_cache=$REPO_CACHE" \
  "--experimental_downloader_config=$DL_CONFIG" \
  //:integration_test

#############
# TODO: Test WORKSPACE
