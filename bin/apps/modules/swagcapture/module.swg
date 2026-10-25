#import("gui", location: "swag@std")

#static if not #hastag("Swag.AllocatorDiagnostics") and
           (#hastag("capture.track-memory") or #hastag("capture.electric-memory") or #hastag("capture.fill-memory"))
{
    #error("Swag Capture memory diagnostics need '--tag Swag.AllocatorDiagnostics'")
}

#run
{
    with let cfg = unwrap Swag.compiler().getBuildCfg()
    {
        .moduleVersion  = #swcversion
        .moduleRevision = #swcrevision
        .moduleBuildNum = #swcbuildnum
        .backendKind    = .Executable
        .backendSubKind = .Default

        #static if #hastag("Swag.AllocatorDiagnostics")
        {
            .allocatorLeaks            = true
            .allocatorCaptureStack     = false
            .allocatorTrackAllocations = #hastag("capture.track-memory")
            .allocatorElectricMode     = #hastag("capture.electric-memory")
            .allocatorFillMemory       = #hastag("capture.fill-memory")
        }

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
