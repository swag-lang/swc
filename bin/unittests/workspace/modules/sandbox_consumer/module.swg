#import("core", location: "swag@std")
#import("runtime_context_bridge")
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "SandboxConsumer"
    cfg.backendKind     = .Executable
}
