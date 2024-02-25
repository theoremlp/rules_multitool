"multitool"

load("//multitool/private:multitool.bzl", _hub = "hub")

hub = tag_class(
    attrs = {
        "lockfile": attr.label(mandatory = True, allow_single_file = True),
    },
)

def _extension(module_ctx):
    lockfiles = []
    for mod in module_ctx.modules:
        for h in mod.tags.hub:
            lockfiles.append(h.lockfile)

    # TODO: we should be able to support multiple hubs
    _hub(
        name = "multitool",
        lockfiles = lockfiles,
    )

multitool = module_extension(
    implementation = _extension,
    tag_classes = {
        "hub": hub,
    },
)
