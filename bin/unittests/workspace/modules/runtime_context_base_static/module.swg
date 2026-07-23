
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "RuntimeCtxBase"
    cfg.backendKind     = .StaticLibrary
}
