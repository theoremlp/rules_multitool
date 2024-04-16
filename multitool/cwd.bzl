"cwd: a rule for executing an executable in the BUILD_WORKING_DIRECTORY"

def _cwd_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(
        content = "\n".join([
            "#!/usr/bin/env bash",
            "execdir=\"$PWD\"",
            "pushd $BUILD_WORKING_DIRECTORY > /dev/null",
            "\"$execdir/{tool}\" \"$@\"".format(tool = ctx.file.tool.short_path),
            "popd > /dev/null",
            "",
        ]),
        output = output,
    )
    return [DefaultInfo(executable = output, runfiles = ctx.runfiles(files = [ctx.file.tool]))]

cwd = rule(
    implementation = _cwd_impl,
    attrs = {
        "tool": attr.label(mandatory = True, allow_single_file = True, executable = True, cfg = "exec"),
    },
    executable = True,
)
