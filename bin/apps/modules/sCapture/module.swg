#import("gui", location: "swag@std")

#run
{
    with let cfg = @compiler.getBuildCfg()!
    {
        .moduleVersion  = #swcversion
        .moduleRevision = #swcrevision
        .moduleBuildNum = #swcbuildnum
        .backendKind    = .Executable
        .backendSubKind = .Default

        // Leak reporting stays on in every build; the heavier allocator
        // instrumentation is opt-in through a build tag.
        .allocatorLeaks            = true
        .allocatorCaptureStack     = false
        .allocatorTrackAllocations = #hastag("sCapture.TrackMemory")
        .allocatorElectricMode     = #hastag("sCapture.ElectricMemory")
        .allocatorFillMemory       = #hastag("sCapture.FillMemory")

        .name              = "sCapture"
        .resAppName        = "sCapture"
        .resAppDescription = "Screen capture and annotation workspace"
        .resAppIcoFileName = "datas/appicon.ico"
        .ignoreInWorkspace = false
    }
}
