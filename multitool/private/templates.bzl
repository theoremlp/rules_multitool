"multitool templating"

_HUB_TEMPLATE = "//multitool/private:hub_repo_template/{filename}.template"
_HUB_TOOL_TEMPLATE = "//multitool/private:hub_repo_tool_template/{filename}.template"

_TOOL_TEMPLATE = "//multitool/private:tool_repo_template/{filename}.template"
_TOOL_TOOL_TEMPLATE = "//multitool/private:tool_repo_tool_template/{filename}.template"

_WORKSPACE_TEMPLATE = "//multitool/private:workspace_hub_repo_template/{filename}.template"

def _render_tool(rctx, filename, substitutions = None):
    rctx.template(
        filename,
        Label(_TOOL_TEMPLATE.format(filename = filename)),
        substitutions = substitutions or {},
    )

def _render_tool_tool(rctx, tool_name, filename, substitutions = None):
    rctx.template(
        "tools/{tool_name}/{filename}".format(tool_name = tool_name, filename = filename),
        Label(_TOOL_TOOL_TEMPLATE.format(filename = filename)),
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

def _render_tool_repo(hub_name, tool_name, binary):
    name = "{name}.{tool_name}.{os}_{cpu}".format(
        name = hub_name,
        tool_name = tool_name,
        binary = json.encode(binary),
        os = binary["os"],
        cpu = binary["cpu"],
    )
    return "\n".join([
        "    tool_repo(",
        "        name = \"{name}\",".format(name = name),
        "        tool_name = \"{tool_name}\",".format(tool_name = tool_name),
        "        binary = '{binary}',".format(binary = json.encode(binary)),
        "    )",
        "",
    ])

def _render_tool_repos(hub_name, tools):
    if len(tools) == 0:
        # in the case the tool dict is empty, ensure the function body we're
        # templating into is non-empty
        return "    pass\n"

    return "\n".join([
        _render_tool_repo(hub_name, tool_name, binary)
        for tool_name, tool in tools.items()
        for binary in tool["binaries"]
    ])

def _render_workspace(rctx, filename, hub_name, tools):
    rctx.template(
        filename,
        Label(_WORKSPACE_TEMPLATE.format(filename = filename)),
        substitutions = {
            "{tool_repos}": _render_tool_repos(hub_name, tools),
        },
    )

templates = struct(
    hub = _render_hub,
    hub_tool = _render_hub_tool,
    tool = _render_tool,
    tool_tool = _render_tool_tool,
    workspace = _render_workspace,
)
