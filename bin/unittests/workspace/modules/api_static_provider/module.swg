
#import("api_export_provider")

#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.moduleNamespace = "StaticApi"
    cfg.backendKind     = .StaticLibrary
}
