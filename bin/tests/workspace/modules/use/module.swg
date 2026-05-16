#import("dep")
#import("deplib", link: "static-library")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Use"
    cfg.backendKind = .Executable
}
