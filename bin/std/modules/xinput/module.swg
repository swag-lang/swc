// Wrapper for Microsoft DirectX Input.

#import("win32")

#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "XInput"
    cfg.backendKind     = .Export
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/xinput"

    cfg.genDoc.kind            = .Api
    cfg.genDoc.outputName      = "std.xinput"
    cfg.genDoc.css             = "css/style.css"
}
