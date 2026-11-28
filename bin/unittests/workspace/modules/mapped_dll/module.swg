#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "MappedDll"
    cfg.backendKind     = .SharedLibrary
}
