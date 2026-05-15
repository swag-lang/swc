#import("dep")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Use"
    cfg.backendKind = .Executable
}
