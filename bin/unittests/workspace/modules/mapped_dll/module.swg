#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.moduleNamespace = "MappedDll"
    cfg.backendKind     = .SharedLibrary
}
