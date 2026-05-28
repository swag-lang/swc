/*
The truetype module is a pure Swag implementation of the subset of FreeType
needed by the standard library. It keeps the same FT_* API surface so code can
switch from the historical freetype wrapper without source changes.
*/

#import("core")

#run
{
    let itf = @compiler
    let cfg = itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "FreeType"
    cfg.backendKind     = .SharedLibrary
}