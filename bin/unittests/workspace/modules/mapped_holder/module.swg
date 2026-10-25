#import("core", location: "swag@std")
#import("mapped_dll")
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "MappedHolder"
    cfg.backendKind     = .Executable
}
