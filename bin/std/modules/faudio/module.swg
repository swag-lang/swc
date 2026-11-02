/*
Raw FAudio C ABI declarations, based on FAudio 25.05.

See https://github.com/FNA-XNA/FAudio/blob/master/include/FAudio.h for the native contract.
Function pointers borrow the library that supplied them. This module does not load FAudio or
open an audio device; callers load `libFAudio.so.0` before resolving its entry points.
*/
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleVersion     = #swcversion
    cfg.moduleRevision    = #swcrevision
    cfg.moduleBuildNum    = #swcbuildnum
    cfg.moduleNamespace   = "FAudio"
    cfg.backendKind       = .Export
    cfg.repoPath          = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/faudio"
    cfg.genDoc.kind       = .Api
    cfg.genDoc.outputName = "std.faudio"
    cfg.genDoc.icon       = "favicon.svg"
    cfg.genDoc.css        = "css/style.css"
}
