"multitool templating"

_ENV_TEMPLATE = "//multitool/private:env_repo_template/{filename}.template"
_ENV_TOOL_TEMPLATE = "//multitool/private:env_repo_tool_template/{filename}.template"

_HUB_TEMPLATE = "//multitool/private:hub_repo_template/{filename}.template"
_HUB_TOOL_TEMPLATE = "//multitool/private:hub_repo_tool_template/{filename}.template"

def _render_env(rctx, filename, substitutions = None):
    rctx.template(
        filename,
        Label(_ENV_TEMPLATE.format(filename = filename)),
        substitutions = substitutions or {},
    )

def _render_env_tool(rctx, tool_name, filename, substitutions = None):
    rctx.template(
        "tools/{tool_name}/{filename}".format(tool_name = tool_name, filename = filename),
        Label(_ENV_TOOL_TEMPLATE.format(filename = filename)),
        substitutions = {
            "{name}": tool_name,
        } | (substitutions or {}),
    )

def _render_hub(rctx, filename, substitutions = None):
    rctx.template(
        filename,
        Label(_HUB_TEMPLATE.format(filename = filename)),
        substitutions = substitutions or {},
    )

def _render_hub_tool(rctx, tool_name, filename, substitutions = None):
    rctx.template(
        "tools/{tool_name}/{filename}".format(tool_name = tool_name, filename = filename),
        Label(_HUB_TOOL_TEMPLATE.format(filename = filename)),
        substitutions = {
            "{name}": tool_name,
        } | (substitutions or {}),
    )

templates = struct(
    env = _render_env,
    env_tool = _render_env_tool,
    hub = _render_hub,
    hub_tool = _render_hub_tool,
)
