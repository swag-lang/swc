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

        .name              = "sFileScope"
        .resAppName        = "sFileScope"
        .resAppDescription = "Fast universal file viewer"
        .resAppIcoFileName = "datas/appicon.ico"
        .ignoreInWorkspace = false
    }
}
