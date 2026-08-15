#import("gui", location: "swag@std")

#run
{
    with let cfg = @compiler.getBuildCfg()!
    {
        .moduleVersion   = #swcversion
        .moduleRevision  = #swcrevision
        .moduleBuildNum  = #swcbuildnum
        .moduleNamespace = "SFileScopeHtml"
        .backendKind     = #command == Swag.CompilerCommand.Test ? .Executable : .SharedLibrary
        .name            = "sfilescope.html"
    }
}
