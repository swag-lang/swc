
#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.moduleNamespace = "ExportApi"
    cfg.backendKind     = .Export
}
