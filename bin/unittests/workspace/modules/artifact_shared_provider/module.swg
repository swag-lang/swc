#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "SharedArtifactProvider"
    cfg.backendKind = .SharedLibrary
}
