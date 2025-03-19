"rule adding a dummy file to output, for test purpose"

def _add_dummy_file(ctx):
    if ctx.executable.tool.extension == "exe":
        content = "@%s %%*" % ctx.executable.tool.short_path
        script = ctx.actions.declare_file(ctx.label.name + ".bat")
    else:
        content = '#!/usr/bin/env bash\nexec "%s" "$@"' % ctx.executable.tool.short_path
        script = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(script, content, is_executable = True)

    dummy_output_file = ctx.actions.declare_file(ctx.label.name + ".dummy")
    ctx.actions.write(dummy_output_file, "")

    return [DefaultInfo(
        executable = script,
        files = depset([script, dummy_output_file]),
        runfiles = ctx.attr.tool[DefaultInfo].default_runfiles,
    )]

add_dummy_file = rule(
    implementation = _add_dummy_file,
    executable = True,
    attrs = {
        "tool": attr.label(mandatory = True, executable = True, cfg = "exec"),
    },
)
