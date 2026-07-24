// Wrapper for Microsoft XAudio2 library.

#import("win32")

#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "XAudio2"
    cfg.backendKind     = .Export
}
