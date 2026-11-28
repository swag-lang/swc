#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "SourceDependencyProvider"
    cfg.backendKind     = .None
}
