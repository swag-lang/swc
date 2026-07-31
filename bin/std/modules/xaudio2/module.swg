// Wrapper for Microsoft XAudio2 library.

#import("win32")

#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "XAudio2"
    cfg.backendKind     = .Export
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/xaudio2"

    cfg.genDoc.kind       = .Api
    cfg.genDoc.outputName = "std.xaudio2"
    cfg.genDoc.icon       = "favicon.svg"
    cfg.genDoc.css        = "css/style.css"
}
