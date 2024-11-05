#!/usr/bin/env bash

# invoked by release workflow
# (via https://github.com/bazel-contrib/.github/blob/master/.github/workflows/release_ruleset.yaml)

set -o errexit -o nounset -o pipefail

TAG="${GITHUB_REF_NAME}"
PREFIX="rules_multitool-${TAG:1}"
ARCHIVE="rules_multitool-${TAG:1}.tar.gz"

# embed version in MODULE.bazel
perl -pi -e "s/version = \"0\.0\.0\",/version = \"${TAG:1}\",/g" MODULE.bazel

stash_name=`git stash create`;
git archive --format=tar --prefix=${PREFIX}/ "${stash_name}" | gzip > $ARCHIVE

SHA=$(shasum -a 256 $ARCHIVE | awk '{print $1}')

cat << EOF
## Using Bzlmod (preferred)

1. Create a multitool.lock.json ([schema](https://github.com/theoremlp/rules_multitool/blob/main/lockfile.schema.json))
2. Add to your \`MODULE.bazel\` file:

\`\`\`starlark
bazel_dep(name = "rules_multitool", version = "${TAG:1}")

multitool = use_extension("@rules_multitool//multitool:extension.bzl", "multitool")
multitool.hub(lockfile = "//:multitool.lock.json")
use_repo(multitool, "multitool")
\`\`\`

## Using WORKSPACE
1. Create a multitool.lock.json ([schema](https://github.com/theoremlp/rules_multitool/blob/main/lockfile.schema.json))
2. Add to your \`WORKSPACE\` file:

\`\`\`starlark
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "bazel_features",
    sha256 = "06f02b97b6badb3227df2141a4b4622272cdcd2951526f40a888ab5f43897f14",
    strip_prefix = "bazel_features-1.9.0",
    url = "https://github.com/bazel-contrib/bazel_features/releases/download/v1.9.0/bazel_features-v1.9.0.tar.gz",
)

http_archive(
    name = "rules_multitool",
    sha256 = "${SHA}",
    strip_prefix = "rules_multitool-${TAG:1}",
    url = "https://github.com/theoremlp/rules_multitool/releases/download/v${TAG:1}/rules_multitool-${TAG:1}.tar.gz",
)

load("@bazel_features//:deps.bzl", "bazel_features_deps")

bazel_features_deps()

load("@rules_multitool//multitool:multitool.bzl", "multitool")

multitool(
    name = "multitool",
    lockfile = "//:multitool.lock.json",
)

# required since 0.15.0 to enable loading only the tools in use
load("@multitool.workspace//:tools.bzl", "load_tools")

load_tools()
\`\`\`
EOF
