#import("dep")
#import("deplib")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Use"
    cfg.backendKind = .Executable
}
