// Wrapper for Microsoft GDI+ library.

#import("win32")

#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Gdiplus"
    cfg.backendKind     = .Export
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/gdiplus"

    cfg.genDoc.kind       = .Api
    cfg.genDoc.outputName = "std.gdiplus"
    cfg.genDoc.icon       = "favicon.svg"
    cfg.genDoc.css        = "css/style.css"
}
