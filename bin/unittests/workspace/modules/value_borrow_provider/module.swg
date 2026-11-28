#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "BorrowProvider"
    cfg.backendKind     = .None
}
