#import("api_export_provider")
#run
{
    let cfg = @compiler.getBuildCfg()!
    cfg.moduleNamespace = "VerifyExpectations"
    cfg.backendKind     = .Export
}
