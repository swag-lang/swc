#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.moduleNamespace = "BorrowLibrary"
    cfg.backendKind     = .SharedLibrary
}
