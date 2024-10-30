"multitool workspace_root execution rule"

load("@rules_multitool//multitool/private:workspace_root.bzl", _workspace_root = "workspace_root")

workspace_root = _workspace_root
