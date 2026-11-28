#import("runtime_context_dynamic_dep", link: "shared-library")
#import("core", location: "swag@std")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "RuntimeCtxDynamicDll"
    cfg.backendKind     = .SharedLibrary
}
