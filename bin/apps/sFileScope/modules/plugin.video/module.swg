#import("gui", location: "swag@std")
#import("video", location: "swag@std")
#load("../../shared/pluginapi.swg")

#run
{
    with let cfg = @compiler.getBuildCfg()!
    {
        .moduleVersion   = #swcversion
        .moduleRevision  = #swcrevision
        .moduleBuildNum  = #swcbuildnum
        .moduleNamespace = "FileScopePluginVideo"
        .backendKind     = #command == Swag.CompilerCommand.Test ? .Executable : .SharedLibrary
        .name            = "plugin.video"
    }
}
