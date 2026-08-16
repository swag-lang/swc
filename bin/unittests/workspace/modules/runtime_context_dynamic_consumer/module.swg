#import("core", location: "swag@std")

#run
{
    let cfg = @compiler.getBuildCfg()!
    cfg.moduleNamespace = "RuntimeCtxDynamicConsumer"
    cfg.backendKind     = .Executable
}
