
#import("runtime_context_base_static")
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "RuntimeCtxDll"
    cfg.backendKind     = .None
}
