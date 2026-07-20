#global #[Swag.ExplicitNullability]

#import("api_export_provider")

#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "StaticApi"
    cfg.backendKind = .StaticLibrary
}
