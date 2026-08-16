#import("gui", location: "swag@std")
#import("plugin.api")

#run
{
    with let cfg = @compiler.getBuildCfg()!
    {
        .moduleVersion   = #swcversion
        .moduleRevision  = #swcrevision
        .moduleBuildNum  = #swcbuildnum
        .moduleNamespace = "FileScopePluginMarkdown"
        .backendKind     = #command == Swag.CompilerCommand.Test ? .Executable : .SharedLibrary
        .name            = "plugin.markdown"
    }
}
