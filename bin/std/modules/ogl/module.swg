#import("core")
#if #os == Swag.TargetOs.Windows
{
    #import("gdi32")
}

#run
{
    let itf = @compiler
    let cfg = itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Ogl"
    cfg.backendKind     = .SharedLibrary
}
