#import("runtime_scheduler_dll")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "SchedulerConsumer"
    cfg.backendKind     = .Executable
}
