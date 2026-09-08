#import("api_export_provider")
#import("core", location: "swag@std")
#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.moduleNamespace = "VerifyExpectations"
    // Backend diagnostics need generated code; source expectations keep test artifacts uncached.
    cfg.backendKind     = #command == Swag.CompilerCommand.Test ? .Executable : .Export
}
