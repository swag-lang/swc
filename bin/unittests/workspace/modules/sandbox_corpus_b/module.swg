#import("core", location: "swag@std")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "SandboxCorpusB"
    cfg.backendKind     = .Executable
}
