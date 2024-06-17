"cwd: a rule for executing an executable in the BUILD_WORKING_DIRECTORY"

def _cwd_impl(ctx):
    template = ctx.file._template_sh
    wrapper_name = ctx.label.name
    tool_short_path = ctx.file.tool.short_path
    if ctx.file.tool.extension == "exe":
        template = ctx.file._template_bat
        wrapper_name = wrapper_name + ".bat"
        # with runfiles enabled, same as linux:
        tool_short_path = tool_short_path.replace("/", "\\")
        # if runfiles are disabled, this should be "..\"+ctx.file.tool.basename
        # do we need to support disabled runfiles?
    output = ctx.actions.declare_file(wrapper_name)
    ctx.actions.expand_template(
        template = template,
        output = output,
        substitutions = {
            "{{tool}}": tool_short_path,
        },
    )
    return [DefaultInfo(executable = output, runfiles = ctx.runfiles(files = [ctx.file.tool]))]

cwd = rule(
    implementation = _cwd_impl,
    attrs = {
        "tool": attr.label(mandatory = True, allow_single_file = True, executable = True, cfg = "exec"),
        "_template_sh": attr.label(default = "//multitool/private:cwd.template.sh", allow_single_file = True),
        "_template_bat": attr.label(default = "//multitool/private:cwd.template.bat", allow_single_file = True),
    },
    executable = True,
)
