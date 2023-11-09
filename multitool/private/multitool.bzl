"multitool"

_COMMON_FILES_TO_GENERATE = [
    "BUILD.bazel",
    "MODULE.bazel",
    "tool/BUILD.bazel",
    "tool/tool.bzl",
    "toolchain_info.bzl",
    "toolchain_type/BUILD.bazel",
    "toolchain_type/toolchain_type.bzl",
    "WORKSPACE.bazel",
]

_PLATFORMS = [
    ("linux", "arm64"),
    ("linux", "x86_64"),
    ("macos", "arm64"),
    ("macos", "x86_64"),
]
_TEMPLATE = "//multitool/private:external_repo_template/{filename}.template"

def _binary(os, cpu):
    return "{os}_{cpu}_binary".format(os = os, cpu = cpu)

def _template(ctx, filename, substitutions):
    ctx.template(
        filename,
        Label(_TEMPLATE.format(filename = filename)),
        substitutions = substitutions,
    )

def _multitool_impl(ctx):
    substitutions = {
        "{%s}" % substitution: value
        for substitution, value in dict(
            {
                attrname: """    executable = "%s",""" % str(attrval) if attrval else ""
                for os, cpu in _PLATFORMS
                for attrname in [_binary(os, cpu)]
                for attrval in [getattr(ctx.attr, attrname)]
            },
            name = ctx.name,
        ).items()
    }

    for filename in _COMMON_FILES_TO_GENERATE:
        _template(ctx, filename, substitutions)

    attr_keys = dir(ctx.attr)
    for os, cpu in _PLATFORMS:
        if _binary(os, cpu) in attr_keys and getattr(ctx.attr, _binary(os, cpu)) != None:
            _template(ctx, "%s/%s/BUILD.bazel" % (os, cpu), substitutions)

_multitool = repository_rule(
    attrs = {_binary(os, cpu): attr.label() for os, cpu in _PLATFORMS},
    implementation = _multitool_impl,
)

def multitool(name, **kwargs):
    _multitool(name = name, **kwargs)
    native.register_toolchains(*[
        "@{name}//{os}/{cpu}".format(name = name, os = os, cpu = cpu)
        for os, cpu in _PLATFORMS
        if kwargs.get("{os}_{cpu}_binary".format(os = os, cpu = cpu)) != None
    ])
