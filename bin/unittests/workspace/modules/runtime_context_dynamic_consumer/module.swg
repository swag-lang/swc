#import("core", location: "swag@std")

#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.moduleNamespace = "RuntimeCtxDynamicConsumer"
    cfg.backendKind     = .Executable
}
