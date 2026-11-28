#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "BorrowLibrary"
    cfg.backendKind     = .SharedLibrary
}
