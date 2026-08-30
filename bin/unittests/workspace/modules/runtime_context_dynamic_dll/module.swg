#import("core", location: "swag@std")

#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.moduleNamespace = "RuntimeCtxDynamicDll"
    cfg.backendKind     = .SharedLibrary
}
