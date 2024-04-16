"cwd: a rule for executing an executable in the BUILD_WORKING_DIRECTORY"

def _cwd_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.expand_template(
        template = ctx.file._template,
        output = output,
        substitutions = {
            "{{tool}}": ctx.file.tool.short_path,
        },
    )
    return [DefaultInfo(executable = output, runfiles = ctx.runfiles(files = [ctx.file.tool]))]

cwd = rule(
    implementation = _cwd_impl,
    attrs = {
        "tool": attr.label(mandatory = True, allow_single_file = True, executable = True, cfg = "exec"),
        "_template": attr.label(default = "//multitool/private:cwd.template.sh", allow_single_file = True),
    },
    executable = True,
)
