#import("pixel")

#run
{
    let itf = @compiler
    let cfg = itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Gui"
    cfg.backendKind     = .SharedLibrary
    cfg.ignoreInWorkspace = false
}
