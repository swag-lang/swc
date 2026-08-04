#import("gui", location: "swag@std")

#run
{
    with let cfg = notnull @compiler.getBuildCfg()
    {
        .moduleVersion  = #swcversion
        .moduleRevision = #swcrevision
        .moduleBuildNum = #swcbuildnum

        // The integration harness runs headless and reports through stdout, so
        // that build alone needs a console.
        .backendKind    = .Executable
        .backendSubKind = #hastag("SCrypt.Integration") ? .Console : .Default

        .name              = "sCrypt"
        .resAppName        = "sCrypt"
        .resAppDescription = "Encrypted virtual disk for Windows"
        .resAppIcoFileName = "datas/appicon.ico"
        .ignoreInWorkspace = false
    }
}
