#import("audio", location: "swag@std")
#import("core", location: "swag@std")
#run
{
    let cfg = @compiler.getBuildCfg()!
    cfg.moduleNamespace = "SandboxConsumer"
    cfg.backendKind     = .Executable
}
