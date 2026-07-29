#import("core")

#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "TrueType"
    cfg.backendKind     = .SharedLibrary
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/truetype"

    cfg.genDoc.kind            = .Api
    cfg.genDoc.outputName      = "std.truetype"
    cfg.genDoc.css             = "css/style.css"
}
