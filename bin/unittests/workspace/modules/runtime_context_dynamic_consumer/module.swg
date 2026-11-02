// Pin shared Core: the dynamically loaded library was built against that same instance.
// A separate copy here would duplicate allocators and runtime contexts; the compiler cannot
// infer this dependency from the library path computed at run time.
#import("core", location: "swag@std", link: "shared-library")
#static if #os == Swag.TargetOs.Windows
{
    #import("win32", location: "swag@std")
}

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "RuntimeCtxDynamicConsumer"
    cfg.backendKind     = .Executable
}
