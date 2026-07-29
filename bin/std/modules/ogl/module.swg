#import("core")
#static if #os == Swag.TargetOs.Windows
{
    #import("win32")
    #import("gdi32")
}

#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Ogl"
    cfg.backendKind     = .SharedLibrary
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/ogl"

    cfg.genDoc.kind            = .Api
    cfg.genDoc.outputName      = "std.ogl"
    cfg.genDoc.css             = "css/style.css"
}
