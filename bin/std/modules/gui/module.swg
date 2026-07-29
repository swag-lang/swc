#import("pixel")

#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.moduleVersion     = #swcversion
    cfg.moduleRevision    = #swcrevision
    cfg.moduleBuildNum    = #swcbuildnum
    cfg.moduleNamespace   = "Gui"
    cfg.backendKind       = .SharedLibrary
    cfg.ignoreInWorkspace = false
    cfg.repoPath          = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/gui"

    cfg.genDoc.kind            = .Api
    cfg.genDoc.outputName      = "std.gui"
    cfg.genDoc.css             = "css/style.css"
}
