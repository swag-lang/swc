#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.name = "ArtifactProvider"
    cfg.moduleNamespace = "ArtifactProvider"
    cfg.backendKind = .StaticLibrary
}
