#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "LifecycleScriptDep"
    cfg.backendKind     = .SharedLibrary
}
