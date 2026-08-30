// Wrapper for Microsoft Gdi32 library.

#import("win32")

#run
{
    let itf = Swag.compiler()
    let cfg = itf.getBuildCfg()!
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Gdi32"
    cfg.backendKind     = .Export
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/gdi32"

    cfg.genDoc.kind       = .Api
    cfg.genDoc.outputName = "std.gdi32"
    cfg.genDoc.icon       = "favicon.svg"
    cfg.genDoc.css        = "css/style.css"
}
