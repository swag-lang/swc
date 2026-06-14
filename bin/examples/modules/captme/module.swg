#import("gui", location: "swag@std")

#run
{
    let itf = @compiler
    let cfg = itf.getBuildCfg()
    cfg.moduleVersion  = #swcversion
    cfg.moduleRevision = #swcrevision
    cfg.moduleBuildNum = #swcbuildnum
    cfg.backendKind    = .Executable
    cfg.backendSubKind = .Default
    cfg.debugAllocator = false
    cfg.resAppName     = "Captme"
}
