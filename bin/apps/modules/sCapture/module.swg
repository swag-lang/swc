#import("gui", location: "swag@std")

#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.moduleVersion             = #swcversion
    cfg.moduleRevision            = #swcrevision
    cfg.moduleBuildNum            = #swcbuildnum
    cfg.backendKind               = .Executable
    cfg.backendSubKind            = .Default
    cfg.name                      = "sCapture"
    cfg.allocatorCaptureStack     = false
    cfg.allocatorLeaks            = true
    cfg.allocatorTrackAllocations = #hastag("sCapture.TrackMemory")
    cfg.allocatorElectricMode     = #hastag("sCapture.ElectricMemory")
    cfg.allocatorFillMemory       = #hastag("sCapture.FillMemory")
    cfg.resAppName                = "sCapture"
    cfg.resAppDescription         = "Screen capture and annotation workspace"
    cfg.resAppIcoFileName         = "datas/appicon.ico"
    cfg.ignoreInWorkspace         = false
}
