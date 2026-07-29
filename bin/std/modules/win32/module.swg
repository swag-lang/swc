// Wrappers for Microsoft Windows Sdk Libraries.
// 10.0.19041.0

#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Win32"
    cfg.backendKind     = .Export
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/win32"

    cfg.genDoc.kind            = .Api
    cfg.genDoc.outputName      = "std.win32"
    cfg.genDoc.css             = "css/style.css"
}
