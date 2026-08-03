#import("gui", location: "swag@std")

#run
{
    let cfg = notnull @compiler.getBuildCfg()
    cfg.moduleVersion     = #swcversion
    cfg.moduleRevision    = #swcrevision
    cfg.moduleBuildNum    = #swcbuildnum
    cfg.backendKind       = .Executable
    cfg.backendSubKind    = #hastag("SCrypt.Integration") ? .Console : .Default
    cfg.name              = "sCrypt"
    cfg.resAppName        = "sCrypt"
    cfg.resAppDescription = "Encrypted virtual disk for Windows"
    cfg.ignoreInWorkspace = false
}
