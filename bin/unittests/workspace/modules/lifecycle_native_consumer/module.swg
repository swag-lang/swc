#import("lifecycle_script_dep", link: "shared-library")
#import("core", location: "swag@std")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "LifecycleNativeConsumer"
    cfg.backendKind = .Executable
}
