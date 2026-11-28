#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.backendKind         = .None
    cfg.moduleNamespace     = "TransitiveLeaf"
}
