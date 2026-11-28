#import("gui", location: "swag@std")
#import("audio", location: "swag@std")
#import("truetype", location: "swag@std")
#import("video", location: "swag@std")
#import("net", location: "swag@std")

#run
{
    with let cfg = unwrap Swag.compiler().getBuildCfg()
    {
        .moduleVersion  = #swcversion
        .moduleRevision = #swcrevision
        .moduleBuildNum = #swcbuildnum
        .backendKind    = .Executable
        .backendSubKind = .Default

        .name              = "swagscope"
        .resAppName        = "Swag Scope"
        .resAppDescription = "Fast universal file viewer"
        .resAppIcoFileName = "datas/appicon.ico"
        .ignoreInWorkspace = false

    }
}
