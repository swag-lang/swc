#import("core", location: "swag@std")
#import("runtime_context_bridge_dll")
#run
{
    let cfg = @compiler.getBuildCfg()!
    cfg.moduleNamespace = "SandboxConsumer"
    cfg.backendKind     = .Executable
}
