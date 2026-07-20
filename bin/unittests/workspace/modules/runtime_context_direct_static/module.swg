
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "RuntimeCtxDirect"
    cfg.backendKind = .StaticLibrary
}
