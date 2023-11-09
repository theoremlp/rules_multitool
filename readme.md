# rules_multitool

An ergonomic approach to defining a single tool target that resolves to a matching os and CPU architecture variant of the tool.

## Usage

For a quickstart, see the [target-determinator example](examples/workspace_target-determinator/).

Load the ruleset in your **MODULE.bazel**:

```python
bazel_dep(name = "rules_multitool", version = "0.0.0")
```

Define tools in your **WORKSPACE.bazel**:

```python
load("@rules_multitool//multitool:multitool.bzl", "multitool")

# Load OS and architecture-specific binaries
http_file(
    name = "target_determinator_linux_x86_64",
    executable = True,
    sha256 = "c8a09143e9fe6eccc4b27a6be92c5929e5a78034a8d0b4c43dbed4ee539ec903",
    urls = ["https://github.com/bazel-contrib/target-determinator/releases/download/v0.25.0/target-determinator.linux.amd64"],
)

http_file(
    name = "target_determinator_macos_x86_64",
    executable = True,
    sha256 = "8c7245603dede429b978e214ca327c3f3d686a1bc712c1298fca0396a0f25f23",
    urls = ["https://github.com/bazel-contrib/target-determinator/releases/download/v0.25.0/target-determinator.darwin.amd64"],
)

# Declare a combined tool, runnable as `bazel run @[name]//tool`
multitool(
    name = "target-determinator",
    linux_x86_64_binary = "@target_determinator_linux_x86_64//file",
    macos_x86_64_binary = "@target_determinator_macos_x86_64//file",
    # also valid to specify:
    # linux_arm64_binary
    # macos_arm64_binary
)
```
