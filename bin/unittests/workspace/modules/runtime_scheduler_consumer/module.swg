#import("runtime_scheduler_dll", link: "shared-library")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "SchedulerConsumer"
    cfg.backendKind     = .Executable
    cfg.embeddedImports = true
}
