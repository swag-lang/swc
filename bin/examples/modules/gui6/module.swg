#import("gui", location: "swag@std")

#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.moduleVersion     = 0
    cfg.moduleRevision    = 0
    cfg.moduleBuildNum    = 0
    cfg.backendKind       = .Executable
    cfg.ignoreInWorkspace = false
    cfg.backendSubKind    = .Default
}
