#import("core", location: "swag@std")
#static if #os == Swag.TargetOs.Windows
{
    #import("win32", location: "swag@std")
}

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "RuntimeContext"
    cfg.backendKind     = .Executable
}
