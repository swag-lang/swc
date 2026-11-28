#import("runtime_scheduler_provider")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "SchedulerConsumer"
    cfg.backendKind     = .Executable
}
