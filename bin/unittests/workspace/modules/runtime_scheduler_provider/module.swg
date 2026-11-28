#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "SchedulerProvider"
    cfg.backendKind     = .None
}
