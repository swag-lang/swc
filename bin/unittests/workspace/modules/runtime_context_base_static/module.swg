
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "RuntimeCtxBase"
    cfg.backendKind     = .StaticLibrary
}
