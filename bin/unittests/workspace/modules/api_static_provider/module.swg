
#import("api_export_provider")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "StaticApi"
    cfg.backendKind     = .StaticLibrary
}
