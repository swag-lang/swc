// Pinned, and it has to be: this program loads a Swag shared library at run time, and that library
// was built against 'core.dll'. Linking core in here as well would put two copies of it in the
// process — two allocators, two runtime contexts — and nothing the compiler sees says so, because
// the library is named by a path this program computes while it runs.
#import("core", location: "swag@std", link: "shared-library")

#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.moduleNamespace = "RuntimeCtxDynamicConsumer"
    cfg.backendKind     = .Executable
}
