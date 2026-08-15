#import("gui", location: "swag@std")
#import("audio", location: "swag@std")

#run
{
    with let cfg = @compiler.getBuildCfg()!
    {
        .moduleVersion   = #swcversion
        .moduleRevision  = #swcrevision
        .moduleBuildNum  = #swcbuildnum
        .moduleNamespace = "SViewerSound"
        .backendKind     = .SharedLibrary
        .name            = "sviewer.sound"
    }
}
