#import("core")

#run
{
    let itf = @compiler
    let cfg = itf.getBuildCfg()
    cfg.explicitNullability = true
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "TrueType"
    cfg.backendKind     = .SharedLibrary
}
