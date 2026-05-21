#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "StaticApi"
    cfg.backendKind = .StaticLibrary
}
