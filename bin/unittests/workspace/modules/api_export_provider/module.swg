
#run
{
    let cfg = notnull @compiler.getBuildCfg()
    cfg.moduleNamespace = "ExportApi"
    cfg.backendKind     = .Export
}
