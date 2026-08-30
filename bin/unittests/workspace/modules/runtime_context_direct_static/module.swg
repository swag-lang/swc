
#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.embeddedImports = true
    cfg.moduleNamespace = "RuntimeCtxDirect"
    cfg.backendKind     = .StaticLibrary
}
