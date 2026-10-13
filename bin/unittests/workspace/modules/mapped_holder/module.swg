#import("core", location: "swag@std")
#import("mapped_dll")
#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.moduleNamespace = "MappedHolder"
    cfg.backendKind     = .Executable
}
