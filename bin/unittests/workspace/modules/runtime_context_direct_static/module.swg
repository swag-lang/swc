
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "RuntimeCtxDirect"
    cfg.backendKind     = .StaticLibrary
}
