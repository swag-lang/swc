#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "Base"
    cfg.backendKind = .StaticLibrary
}
