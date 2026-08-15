#import("gui", location: "swag@std")

#run
{
    with let cfg = @compiler.getBuildCfg()!
    {
        .moduleVersion   = #swcversion
        .moduleRevision  = #swcrevision
        .moduleBuildNum  = #swcbuildnum
        .moduleNamespace = "SFileScopeImage"
        .backendKind     = .SharedLibrary
        .name            = "sfilescope.image"
    }
}
