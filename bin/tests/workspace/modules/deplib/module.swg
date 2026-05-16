#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "DepLib"
    cfg.backendKind = .StaticLibrary
}
