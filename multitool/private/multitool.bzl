"multitool hub implementation"

_HUB_TEMPLATE = "//multitool/private:hub_repo_template/{filename}.template"
_TOOL_TEMPLATE = "//multitool/private:tool_template/{filename}.template"

def _render_hub(rctx, filename, substitutions = None):
    rctx.template(
        filename,
        Label(_HUB_TEMPLATE.format(filename = filename)),
        substitutions = substitutions or {},
    )

def _render_tool(rctx, tool_name, filename, substitutions = None):
    rctx.template(
        "tools/{tool_name}/{filename}".format(tool_name = tool_name, filename = filename),
        Label(_TOOL_TEMPLATE.format(filename = filename)),
        substitutions = {
            "{name}": tool_name,
        } | (substitutions or {}),
    )

def _check(condition, message):
    "fails iff condition is False and emits message"
    if not condition:
        fail(message)

def _match_os(rctx, os):
    # rctx.os.name takes values from Java system property `os.name`
    if os == "macos" and rctx.os.name.startswith("mac"):
        return True
    if os == "linux" and rctx.os.name.lower() == "linux":
        return True
    return False

def _match_cpu(rctx, cpu):
    # rctx.os.arch takes values from Java system property `os.arch`
    if cpu == "x86_64" and rctx.os.arch == "x86_64":
        return True
    if cpu == "arm64" and rctx.os.arch == "aarch64":
        return True
    return False

def _match_local(rctx, os, cpu):
    "Returns True iff os and cpu match local environment"
    return _match_os(rctx, os) and _match_cpu(rctx, cpu)

def _multitool_hub_impl(rctx):
    tools = {}
    for lockfile in rctx.attr.lockfiles:
        # TODO: validate no conflicts from multiple hub declarations and/or
        #  fix toolchains to also declare their versions and enable consumers
        #  to use constraints to pick the right one.
        #  (this is also a very naive merge at the tool level)
        tools = tools | json.decode(rctx.read(lockfile))

    loads = []
    defines = []

    for tool_name, tool in tools.items():
        toolchains = []

        for binary in tool["binaries"]:
            _check(binary["os"] in ["linux", "macos"], "Unknown os '{os}'".format(os = binary["os"]))
            _check(binary["cpu"] in ["x86_64", "arm64"], "Unknown cpu '{cpu}'".format(cpu = binary["cpu"]))

            if not _match_local(rctx, binary["os"], binary["cpu"]):
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

            toolchains.append('\n    _declare_toolchain(name="{name}", os="{os}", cpu="{cpu}")'.format(
                name = tool_name,
                cpu = binary["cpu"],
                os = binary["os"],
            ))

        _render_tool(rctx, tool_name, "BUILD.bazel")
        _render_tool(rctx, tool_name, "tool.bzl", {
            "{toolchains}": "\n".join(toolchains),
        })

        clean_name = tool_name.replace("-", "_")
        loads.append('load("//tools/{tool_name}:tool.bzl", declare_{clean_name}_toolchains = "declare_toolchains")'.format(
            tool_name = tool_name,
            clean_name = clean_name,
        ))
        defines.append("declare_{clean_name}_toolchains()".format(clean_name = clean_name))

    _render_hub(rctx, "BUILD.bazel")
    _render_hub(rctx, "toolchain_info.bzl")
    _render_hub(rctx, "tools/BUILD.bazel")
    _render_hub(rctx, "toolchains/BUILD.bazel", {
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
    _multitool_hub(name = name, lockfiles = lockfiles)

def multitool(name, lockfile):
    "(non-bzlmod) Create a multitool hub and register its toolchains."

    _multitool_hub(name = name, lockfiles = [lockfile])

    native.register_toolchains("@multitool//toolchains:all")
