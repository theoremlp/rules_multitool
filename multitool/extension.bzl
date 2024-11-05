"multitool module extension"

load("//multitool/private:multitool.bzl", _hub = "bzlmod_hub")

hub = tag_class(
    attrs = {
        "lockfile": attr.label(mandatory = True, allow_single_file = True),
    },
)

def _extension(module_ctx):
    lockfiles = []
    for mod in reversed(module_ctx.modules):
        for h in mod.tags.hub:
            lockfiles.append(h.lockfile)

    # TODO: we should be able to support multiple hubs
    _hub(
        name = "multitool",
        lockfiles = lockfiles,
        module_ctx = module_ctx,
    )

    return module_ctx.extension_metadata(
        root_module_direct_deps = ["multitool"],
        root_module_direct_dev_deps = [],
    )

multitool = module_extension(
    implementation = _extension,
    tag_classes = {
        "hub": hub,
    },
)
