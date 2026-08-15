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

        .name              = "sViewer"
        .resAppName        = "sViewer"
        .resAppDescription = "Fast universal file viewer"
        .resAppIcoFileName = "datas/appicon.ico"
        .ignoreInWorkspace = false
    }
}
