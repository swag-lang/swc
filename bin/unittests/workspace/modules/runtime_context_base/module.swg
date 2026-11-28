
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "RuntimeCtxBase"
    cfg.backendKind     = .None
}
