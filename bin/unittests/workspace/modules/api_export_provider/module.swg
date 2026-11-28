
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "ExportApi"
    cfg.backendKind     = .Export
}
