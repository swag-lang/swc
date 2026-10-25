#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "SchedulerDll"
    cfg.backendKind     = .SharedLibrary
    cfg.embeddedImports = true
}
