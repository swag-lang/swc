#import("core", location: "swag@std")

#run
{
    let cfg = @compiler.getBuildCfg()!
    cfg.moduleNamespace = "RuntimeCtxDynamicDll"
    cfg.backendKind     = .SharedLibrary
}
