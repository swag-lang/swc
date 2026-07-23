
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "ExportApi"
    cfg.backendKind     = .Export
}
