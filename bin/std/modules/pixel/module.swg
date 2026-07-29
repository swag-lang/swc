#import("core")
#import("ogl")
#import("truetype")

#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Pixel"
    cfg.backendKind     = .SharedLibrary
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/pixel"

    cfg.genDoc.kind            = .Api
    cfg.genDoc.outputName      = "std.pixel"
    cfg.genDoc.css             = "css/style.css"
}
