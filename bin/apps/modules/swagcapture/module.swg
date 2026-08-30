#import("gui", location: "swag@std")

#run
{
    with let cfg = Swag.compiler().getBuildCfg()!
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
        .allocatorTrackAllocations = #hastag("capture.track-memory")
        .allocatorElectricMode     = #hastag("capture.electric-memory")
        .allocatorFillMemory       = #hastag("capture.fill-memory")

        .name              = "swagcapture"
        .resAppName        = "Swag Capture"
        .resAppDescription = "Screen capture and annotation workspace"
        .resAppIcoFileName = "datas/appicon.ico"
        .ignoreInWorkspace = false

        // A shipped application is launched from its own directory, so the link places the
        // shared libraries it needs beside it.
        .publishDependencies = true
    }
}
