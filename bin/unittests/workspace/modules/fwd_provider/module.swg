#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "FwdProvider"
    cfg.backendKind = .SharedLibrary
}
