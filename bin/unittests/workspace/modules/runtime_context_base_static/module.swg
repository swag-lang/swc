
#run
{
    let cfg = notnull @compiler.getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "RuntimeCtxBase"
    cfg.backendKind     = .StaticLibrary
}
