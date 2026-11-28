
#import("runtime_context_base")
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "RuntimeCtxBridge"
    cfg.backendKind     = .None
}
