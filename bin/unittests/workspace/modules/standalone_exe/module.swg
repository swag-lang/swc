// An executable that names no link kind. Its dependencies are shared libraries, and it is what
// proves the default: their code is linked in, so the executable runs on its own with no library
// beside it. 'consumer_exe' pins one import and covers the opposite answer.
#import("runtime_context_bridge_dll")
#import("core", location: "swag@std")

#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.moduleNamespace      = "StandaloneExe"
    cfg.backendKind          = .Executable
    cfg.publishDependencies  = true
}
