#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.backendKind = .SharedLibrary
    cfg.moduleNamespace = "TransitiveLeaf"
    cfg.publishDependencies = false
}
