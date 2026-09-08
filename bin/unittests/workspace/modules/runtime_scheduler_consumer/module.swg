#import("runtime_scheduler_dll", link: "shared-library")

#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.moduleNamespace = "SchedulerConsumer"
    cfg.backendKind     = .Executable
    cfg.embeddedImports = true
}
