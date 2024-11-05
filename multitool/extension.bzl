"multitool module extension"

load("//multitool/private:multitool.bzl", _hub = "bzlmod_hub")

_DEFAULT_HUB_NAME = "multitool"

hub = tag_class(
    attrs = {
        "hub_name": attr.string(default = _DEFAULT_HUB_NAME),
        "lockfile": attr.label(mandatory = True, allow_single_file = True),
    },
)

def _extension(module_ctx):
    lockfiles = {
        _DEFAULT_HUB_NAME: [],
    }
    for mod in reversed(module_ctx.modules):
        for h in mod.tags.hub:
            if h.hub_name in lockfiles:
                lockfiles[h.hub_name].append(h.lockfile)
            else:
                lockfiles[h.hub_name] = [h.lockfile]

    for lockfile_name, lockfile_list in lockfiles.items():
        _hub(
            name = lockfile_name,
            lockfiles = lockfile_list,
            module_ctx = module_ctx,
        )

    return module_ctx.extension_metadata(
        root_module_direct_deps = lockfiles.keys(),
        root_module_direct_dev_deps = [],
        reproducible = True,  # repo state is only a function of the lockfile
    )

multitool = module_extension(
    implementation = _extension,
    tag_classes = {
        "hub": hub,
    },
)
