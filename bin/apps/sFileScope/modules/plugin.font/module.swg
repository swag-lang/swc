#import("gui", location: "swag@std")
#import("truetype", location: "swag@std")
#load("../../shared/pluginapi.swg")

#run
{
    with let cfg = @compiler.getBuildCfg()!
    {
        .moduleVersion   = #swcversion
        .moduleRevision  = #swcrevision
        .moduleBuildNum  = #swcbuildnum
        .moduleNamespace = "FileScopePluginFont"
        .backendKind     = #command == Swag.CompilerCommand.Test ? .Executable : .SharedLibrary
        .name            = "plugin.font"
    }
}
