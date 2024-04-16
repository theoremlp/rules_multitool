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

### Running tools in the current working directory

When running `@multitool//tools/tool-name`, Bazel will execute the tool at the root of the runfiles tree due to https://github.com/bazelbuild/bazel/issues/3325.

To run a tool in the current working directory, use the convenience target `@multitool//tools/tool-name:cwd`.

A common pattern we recommend to further simplify invoking tools for repository users it to:

1.  Create a `tools/` directory
1.  Create an executable shell script `tools/_run_multitool.sh` with the following code:
    ```sh
    #!/usr/bin/env bash
    bazel run "@multitool//tools/$( basename $0 ):cwd" -- "$@"
    ```
1.  Create symlinks of `tools/tool-name` to `tools/_run_multitool.sh`
