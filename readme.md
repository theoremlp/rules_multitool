# rules_multitool

An ergonomic approach to defining a single tool target that resolves to a matching os and CPU architecture variant of the tool.

## Usage

For a quickstart, see the [module example](examples/module/) or [workspace example](examples/workspace/).

Define a [lockfile](lockfile.schema.json) that references the tools to load:

```json
{
  "$schema": "https://raw.githubusercontent.com/theoremlp/rules_multitool/main/lockfile.schema.json",
  "tool-name": {
    "binaries": [
      {
        "kind": "file",
        "url": "https://...",
        "sha256": "sha256 of the file",
        "os": "linux|macos",
        "cpu": "x86_64|arm64"
      }
    ]
  }
}
```

The lockfile supports the following binary kinds:

- **file**: the URL refers to a file to download

  - `sha256`: the sha256 of the downloaded file

- **archive**: the URL referes to an archive to download, specify additional options:

  - `file`: executable file within the archive
  - `sha256`: the sha256 of the downloaded archive

- **pkg**: the URL refers to a MacOS pkg archive to download, specify additional options:

  - `file`: executable file within the archive
  - `sha256`: the sha256 of the downloaded pkg archive

Save your lockfile and ensure the file is exported using `export_files` so that it's available to Bazel.

### Bazel Module Usage

Once your lockfile is defined, load the ruleset in your MODULE.bazel and create a hub that refers to your lockfile:

```python
bazel_dep(name = "rules_multitool", version = "0.0.0")

multitool = use_extension("@rules_multitool//multitool:extension.bzl", "multitool")
multitool.hub(lockfile = "//:multitool.lock.json")
use_repo(multitool, "multitool")
```

Tools may then be accessed using `@multitool//tools/tool-name`.

### Workspace Usage

Instructions for using with WORKSPACE may be found in [release notes](https://github.com/theoremlp/rules_multitool/releases).

### Creating convenience scripts

When users need to execute tools directly, Bazel does not provide very good support for this,
because it sets the working directory to the root of the runfiles tree, which breaks the ability of the tool to resolve configuration files and other relative paths.

The typical workarounds are all bad:

1. Change all paths the tool interacts with to be absolute, so that the working directory is inconsequential.
2. Wrap the tool in a trivial `sh_binary` that can read `$BUILD_WORKING_DIRECTORY`.
3. Use `--run_under="cd $PWD &&` however this [discards the analysis cache] slowing down this and the subsequent build.

Instead, the authors recommend the following technique. Create a script like `tools/_multitool_run_under_cwd.sh` containing the following shell code:

```sh
#!/bin/bash
# Workaround https://github.com/bazelbuild/bazel/issues/3325
target="@multitool//tools/$(basename "$0")"
bazel build "$target" && exec $(bazel 2>/dev/null cquery --output=files "$target") "$@"
```

Now just create symlinks such as `tools/mytool -> ./_multitool_run_under_cwd.sh`.
This will build `@multitool//tools/mytool` and then execute the resulting binary in the current working directory.

[discards the analysis cache]: https://github.com/bazelbuild/bazel/issues/10782
