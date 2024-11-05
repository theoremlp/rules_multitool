"multitool workspace macros"

load("//multitool/private:multitool.bzl", "workspace_hub")

def multitool(name, lockfile = None, lockfiles = None):
    """(non-bzlmod) Create a multitool hub and register its toolchains.

    Args:
        name: resulting "hub" repo name to load tools from
        lockfile: a label for a lockfile, see /lockfile.schema.json
        lockfiles: a list of labels of multiple lockfiles

    Note: exactly one of lockfile or lockfiles may be set.
    """
    if (not lockfile and not lockfiles) or (lockfile and lockfiles):
        fail("Exactly one of lockfile and lockfiles must be set")

    lockfiles = lockfiles if lockfiles else [lockfile]

    workspace_hub(name, lockfiles)
    native.register_toolchains("@{name}//toolchains:all".format(name = name))
