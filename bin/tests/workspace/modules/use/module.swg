#import("dep")
#import("deplib", link: "static-library")
#import("ctxshared")
#import("ctxdirect", link: "static-library")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "Use"
    cfg.backendKind = .Executable
}
