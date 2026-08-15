#import("gui", location: "swag@std")

#run
{
    with let cfg = @compiler.getBuildCfg()!
    {
        .moduleVersion  = #swcversion
        .moduleRevision = #swcrevision
        .moduleBuildNum = #swcbuildnum

        // The integration harness runs headless and reports through stdout, so
        // that build alone needs a console.
        .backendKind    = .Executable
        .backendSubKind = #hastag("SVaultDrive.Integration") ? .Console : .Default

        .name              = "sVaultDrive"
        .resAppName        = "sVaultDrive"
        .resAppDescription = "Encrypted virtual disk for Windows"
        .resAppIcoFileName = "datas/appicon.ico"
        .ignoreInWorkspace = false
    }
}
