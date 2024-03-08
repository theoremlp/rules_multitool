"""
multitool

Multitool takes as input a JSON lockfile and emits the following repos:

 - [hub].[os]_[cpu], for each [os]/[cpu] combo in _SUPPORTED_ENVS:
     This repository holds os/cpu specific binaries for all tools in the provided
     lockfile(s) and constructs clean symlinks to their content for inclusion in
     toolchains defined in the [hub] repo.

     The structure of this repo is, very simply:
       tools/
         [tool-name]/
           BUILD.bazel            (export all *_executable files)
           [os]_[cpu]_executable  (a downloaded file or a symlink to a file in a
                                   downloaded and extracted archive)

 - [hub]:
     This repository holds toolchain definitions for all tools in the provided
     lockfile(s), as well as an executable tool target that will pick the
     appropriate toolchain.

     The structure of this repo is:
       toolchains/
         BUILD.bazel      (a single file containing all declared toolchains for easy registration)
       tools/
         [tool-name]/
           BUILD.bazel    (declares the toolchain_type and the executable tool target)
           tool.bzl       (scaffolding for the tool target and toolchain declarations in toolchains/BUILD.bazel)
       toolchain_info.bzl (common scaffolding for toolchain declarations)

       (additional BUILD.bazel and a WORKSPACE file are included as required by Bazel)

To keep things orderly, we keep all the toolchain Bazel goo in the [hub] repo and only stash
the binaries in the [hub].[os]_[cpu] repos. It's a conscious decision not to place some fragments
of the toolchain definitions in the latter repos to make the dependencies run exactly one way:
[hub] -> [hub].[os]_[cpu].

This implementation depends on rendering a number of templates, which are defined in sibling
folders and managed by the templates starlark file.

To maintain support both bzlmod and non-bzlmod setups, we provide two entrypoints to the rule:
 - (bzlmod)     hub       : invoked by the hub tag in extension.bzl
 - (non-bzlmod) multitool : invoked in WORKSPACE or related macros, and additionally registers toolchains
"""

load(":templates.bzl", "templates")

_SUPPORTED_ENVS = [
    ("linux", "arm64"),
    ("linux", "x86_64"),
    ("macos", "arm64"),
    ("macos", "x86_64"),
]

def _check(condition, message):
    "fails iff condition is False and emits message"
    if not condition:
        fail(message)

def _load_tools(rctx):
    tools = {}
    for lockfile in rctx.attr.lockfiles:
        # TODO: validate no conflicts from multiple hub declarations and/or
        #  fix toolchains to also declare their versions and enable consumers
        #  to use constraints to pick the right one.
        #  (this is also a very naive merge at the tool level)
        tools = tools | json.decode(rctx.read(lockfile))

    # a special key says this JSON document conforms to a schema
    tools.pop("$schema", None)

    # validation
    for tool_name, tool in tools.items():
        for binary in tool["binaries"]:
            _check(
                binary["os"] in ["linux", "macos"],
                "{tool_name}: Unknown os '{os}'".format(
                    tool_name = tool_name,
                    os = binary["os"],
                ),
            )
            _check(
                binary["cpu"] in ["x86_64", "arm64"],
                "{tool_name}: Unknown cpu '{cpu}'".format(
                    tool_name = tool_name,
                    cpu = binary["cpu"],
                ),
            )

    return tools

def _env_specific_tools_impl(rctx):
    tools = _load_tools(rctx)

    for tool_name, tool in tools.items():
        for binary in tool["binaries"]:
            if binary["os"] != rctx.attr.os or binary["cpu"] != rctx.attr.cpu:
                continue

            target_executable = "tools/{tool_name}/{os}_{cpu}_executable".format(
                tool_name = tool_name,
                cpu = binary["cpu"],
                os = binary["os"],
            )

            if binary["kind"] == "file":
                rctx.download(
                    url = binary["url"],
                    sha256 = binary["sha256"],
                    output = target_executable,
                    executable = True,
                )
            elif binary["kind"] == "archive":
                archive_path = "tools/{tool_name}/{os}_{cpu}_archive".format(
                    tool_name = tool_name,
                    cpu = binary["cpu"],
                    os = binary["os"],
                )

                rctx.download_and_extract(
                    url = binary["url"],
                    sha256 = binary["sha256"],
                    output = archive_path,
                )

                # link to the executable
                rctx.symlink(
                    "{archive_path}/{file}".format(archive_path = archive_path, file = binary["file"]),
                    target_executable,
                )
            elif binary["kind"] == "pkg":
                # Check if pkgutil is on the path, and if not fail silently.
                # repository rules execute irrespective of platform/OS, so this
                # check is required for `pkg_archive` to not fail on Linux.
                pkgutil_cmd = rctx.which("pkgutil")
                if not pkgutil_cmd:
                    continue

                archive_path = "tools/{tool_name}/{os}_{cpu}_pkg".format(
                    tool_name = tool_name,
                    cpu = binary["cpu"],
                    os = binary["os"],
                )

                rctx.download(
                    url = binary["url"],
                    sha256 = binary["sha256"],
                    output = archive_path + ".pkg",
                )

                rctx.execute([pkgutil_cmd, "--expand-full", archive_path + ".pkg", archive_path])

                # link to the executable
                rctx.symlink(
                    "{archive_path}/{file}".format(archive_path = archive_path, file = binary["file"]),
                    target_executable,
                )
            else:
                fail("Unknown 'kind' {kind}".format(kind = binary["kind"]))

            templates.env_tool(rctx, tool_name, "BUILD.bazel")

    templates.env(rctx, "tools/BUILD.bazel")
    templates.env(rctx, "BUILD.bazel")

_env_specific_tools = repository_rule(
    attrs = {
        "lockfiles": attr.label_list(mandatory = True, allow_files = True),
        "os": attr.string(),
        "cpu": attr.string(),
    },
    implementation = _env_specific_tools_impl,
)

def _sort_fn(tup):
    return tup[0]

def _multitool_hub_impl(rctx):
    tools = _load_tools(rctx)

    loads = []
    defines = []

    for tool_name, tool in sorted(tools.items(), key = _sort_fn):
        toolchains = []

        for binary in tool["binaries"]:
            toolchains.append('\n    _declare_toolchain(name="{name}", os="{os}", cpu="{cpu}")'.format(
                name = tool_name,
                cpu = binary["cpu"],
                os = binary["os"],
            ))

        templates.hub_tool(rctx, tool_name, "BUILD.bazel")
        templates.hub_tool(rctx, tool_name, "tool.bzl", {
            "{hub_name}": rctx.attr.name,
            "{toolchains}": "\n".join(toolchains),
        })

        clean_name = tool_name.replace("-", "_")
        loads.append('load("//tools/{tool_name}:tool.bzl", declare_{clean_name}_toolchains = "declare_toolchains")'.format(
            tool_name = tool_name,
            clean_name = clean_name,
        ))
        defines.append("declare_{clean_name}_toolchains()".format(clean_name = clean_name))

    templates.hub(rctx, "BUILD.bazel")
    templates.hub(rctx, "toolchain_info.bzl")
    templates.hub(rctx, "tools/BUILD.bazel")
    templates.hub(rctx, "toolchains/BUILD.bazel", {
        "{loads}": "\n".join(loads),
        "{defines}": "\n".join(defines),
    })

_multitool_hub = repository_rule(
    attrs = {
        "lockfiles": attr.label_list(mandatory = True, allow_files = True),
    },
    implementation = _multitool_hub_impl,
)

def hub(name, lockfiles):
    "Create a multitool hub."
    for env in _SUPPORTED_ENVS:
        _env_specific_tools(
            name = "{name}.{os}_{cpu}".format(name = name, os = env[0], cpu = env[1]),
            lockfiles = lockfiles,
            os = env[0],
            cpu = env[1],
        )
    _multitool_hub(name = name, lockfiles = lockfiles)

def multitool(name, lockfile):
    "(non-bzlmod) Create a multitool hub and register its toolchains."
    hub(name, [lockfile])
    native.register_toolchains("@{name}//toolchains:all".format(name = name))
