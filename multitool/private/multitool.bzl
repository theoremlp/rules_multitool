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

Note that we intend to support both bzlmod and non-bzlmod setups, so `hub` intentionally avoids
a register_toolchains call.
"""

load("@bazel_features//:features.bzl", "bazel_features")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "read_netrc", "read_user_netrc", "use_netrc")
load(":templates.bzl", "templates")

_SUPPORTED_ENVS = [
    ("linux", "arm64"),
    ("linux", "x86_64"),
    ("macos", "arm64"),
    ("macos", "x86_64"),
    ("windows", "arm64"),
    ("windows", "x86_64"),
]

def _check(condition, message):
    "fails iff condition is False and emits message"
    if not condition:
        fail(message)

def _check_version(os, binary_os):
    # require bazel 7.1 on windows. Only do this check for windows artifacts to avoid regressing anyone
    # skip version check on windows if we don't have a release version. We can't tell from a hash what features we have.
    if os == "windows" and binary_os == "windows" and native.bazel_version:
        version = native.bazel_version.split(".")
        if int(version[0]) > 7 or (int(version[0]) == 7 and int(version[1]) >= 1):
            pass
        else:
            fail("rules_multitool: windows platform requires bazel 7.1+ to read artifacts; current bazel is " + native.bazel_version)

def _get_auth(rctx, urls, auth_patterns):
    "Returns an auth dict for the provided list of URLs."
    if "NETRC" in rctx.os.environ:
        netrc = read_netrc(rctx, rctx.os.environ["NETRC"])
    else:
        netrc = read_user_netrc(rctx)
    return use_netrc(netrc, urls, auth_patterns)

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
                binary["os"] in ["linux", "macos", "windows"],
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
            _check_version(rctx.os.name, binary["os"])

    return tools

def _feature_sensitive_args(binary):
    args = {}
    if bazel_features.external_deps.download_has_headers_param:
        args["headers"] = binary.get("headers", {})

    return args

def _extension(os):
    if os == "windows":
        return ".exe"
    return ""

def _env_specific_tools_impl(rctx):
    tools = _load_tools(rctx)

    for tool_name, tool in tools.items():
        for binary in tool["binaries"]:
            if binary["os"] != rctx.attr.os or binary["cpu"] != rctx.attr.cpu:
                continue

            target_filename = "{os}_{cpu}_executable{ext}".format(
                cpu = binary["cpu"],
                os = binary["os"],
                ext = _extension(binary["os"]),
            )
            target_executable = "tools/{tool_name}/{filename}".format(
                tool_name = tool_name,
                filename = target_filename,
            )

            if binary["kind"] == "file":
                rctx.download(
                    url = binary["url"],
                    sha256 = binary["sha256"],
                    output = target_executable,
                    executable = True,
                    auth = _get_auth(rctx, [binary["url"]], binary.get("auth_patterns", {})),
                    **_feature_sensitive_args(binary)
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
                    type = binary.get("type", ""),
                    auth = _get_auth(rctx, [binary["url"]], binary.get("auth_patterns", {})),
                    **_feature_sensitive_args(binary)
                )

                # link to the executable
                archive_file = "{archive_path}/{file}".format(archive_path = archive_path, file = binary["file"])
                if not rctx.path(archive_file).exists:
                    fail("{tool_name} ({os}, {cpu}): Cannot find {file} in archive from {url}".format(
                        tool_name = tool_name,
                        os = binary["os"],
                        cpu = binary["cpu"],
                        file = archive_file,
                        url = binary["url"],
                    ))
                rctx.symlink(archive_file, target_executable)
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
                    auth = _get_auth(rctx, [binary["url"]], binary.get("auth_patterns", {})),
                    **_feature_sensitive_args(binary)
                )

                rctx.execute([pkgutil_cmd, "--expand-full", archive_path + ".pkg", archive_path])

                # link to the executable
                archive_file = "{archive_path}/{file}".format(archive_path = archive_path, file = binary["file"])
                if not rctx.path(archive_file).exists:
                    fail("{tool_name} ({os}, {cpu}): Cannot find {file} in archive from {url}".format(
                        tool_name = tool_name,
                        os = binary["os"],
                        cpu = binary["cpu"],
                        file = archive_file,
                        url = binary["url"],
                    ))
                rctx.symlink(archive_file, target_executable)
            else:
                fail("Unknown 'kind' {kind}".format(kind = binary["kind"]))

            templates.env_tool(rctx, tool_name, "BUILD.bazel", {"{target_filename}": target_filename})

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
            toolchains.append('\n    declare_toolchain(name="{name}", os="{os}", cpu="{cpu}", toolchain_type=_TOOLCHAIN_TYPE)'.format(
                name = tool_name,
                cpu = binary["cpu"],
                os = binary["os"],
            ))

        templates.hub_tool(rctx, tool_name, "BUILD.bazel")
        templates.hub_tool(rctx, tool_name, "tool.bzl", {
            "{toolchains}": "\n".join(toolchains),
        })

        clean_name = tool_name.replace("-", "_")
        loads.append('load("//tools/{tool_name}:tool.bzl", declare_{clean_name}_toolchains = "declare_toolchains")'.format(
            tool_name = tool_name,
            clean_name = clean_name,
        ))
        defines.append("declare_{clean_name}_toolchains()".format(clean_name = clean_name))

    templates.hub(rctx, "BUILD.bazel")
    templates.hub(rctx, "toolchain_info.bzl", {
        "{hub_name}": rctx.attr.name,
    })
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
