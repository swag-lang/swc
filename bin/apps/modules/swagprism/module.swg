#import("gui", location: "swag@std")

#run
{
    with let cfg = Swag.compiler().getBuildCfg()!
    {
        .moduleVersion  = #swcversion
        .moduleRevision = #swcrevision
        .moduleBuildNum = #swcbuildnum
        .backendKind    = .Executable
        .backendSubKind = .Default

        .name              = "swagprism"
        .resAppName        = "Swag Prism"
        .resAppDescription = "Live view of what the compiler makes of your code"
        .resAppIcoFileName = "datas/appicon.ico"
        .ignoreInWorkspace = false

        // A shipped application is launched from its own directory, so the link places the
        // shared libraries it needs beside it.
        .publishDependencies = true
    }
}
