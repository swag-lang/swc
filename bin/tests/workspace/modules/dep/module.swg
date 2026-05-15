#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Dep"
    cfg.backendKind = .Export
}
