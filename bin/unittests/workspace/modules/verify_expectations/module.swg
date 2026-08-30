#import("api_export_provider")
#import("core", location: "swag@std")
#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.moduleNamespace = "VerifyExpectations"
    cfg.backendKind     = .Export
}
