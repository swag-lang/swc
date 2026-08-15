#import("gui", location: "swag@std")
#import("audio", location: "swag@std")

#run
{
    with let cfg = @compiler.getBuildCfg()!
    {
        .moduleVersion   = #swcversion
        .moduleRevision  = #swcrevision
        .moduleBuildNum  = #swcbuildnum
        .moduleNamespace = "SFileScopeSound"
        .backendKind     = #command == Swag.CompilerCommand.Test ? .Executable : .SharedLibrary
        .name            = "sfilescope.sound"
    }
}
