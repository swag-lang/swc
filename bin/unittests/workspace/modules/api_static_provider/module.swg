
#import("api_export_provider")

#run
{
    let cfg = notnull @compiler.getBuildCfg()
    cfg.moduleNamespace = "StaticApi"
    cfg.backendKind     = .StaticLibrary
}
