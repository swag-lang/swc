#import("pixel", location: "swag@std")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "PngImportConsumer"
    cfg.backendKind     = .Executable
}
