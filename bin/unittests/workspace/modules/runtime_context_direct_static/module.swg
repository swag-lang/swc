
#run
{
    let cfg = notnull @compiler.getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "RuntimeCtxDirect"
    cfg.backendKind     = .StaticLibrary
}
