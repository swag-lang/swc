#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "Dir"
    cfg.backendKind = .StaticLibrary
}
