/*
Windows SDK bindings used by the standard workspace, including Win32, GDI,
GDI+, XInput, and related system APIs. The API-specific namespaces
`Win32.Gdi32`, `Win32.Gdiplus`, and `Win32.XInput` preserve their upstream
boundaries for callers that need a particular surface.
*/

#run
{
    let itf = Swag.compiler()
    let cfg = unwrap itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Win32"
    cfg.backendKind     = .Export
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/win32"

    cfg.genDoc.kind       = .Api
    cfg.genDoc.outputName = "std.win32"
    cfg.genDoc.icon       = "favicon.svg"
    cfg.genDoc.css        = "css/style.css"
}
