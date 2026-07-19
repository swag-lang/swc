#global #[Swag.ExplicitNullability]
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
    cfg.allocatorCaptureStack     = false
    cfg.allocatorLeaks            = true
    cfg.allocatorTrackAllocations = #hastag("CaptMe.TrackMemory")
    cfg.allocatorElectricMode     = #hastag("CaptMe.ElectricMemory")
    cfg.allocatorFillMemory       = #hastag("CaptMe.FillMemory")
    cfg.resAppName     = "Captme"
}
