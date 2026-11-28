// An executable that names no link kind. Its source dependencies are linked in, so the executable
// runs on its own with no sibling libraries. 'consumer_exe' explicitly selects the same output.
#import("runtime_context_bridge")
#import("core", location: "swag@std")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace     = "StandaloneExe"
    cfg.backendKind         = .Executable
}
