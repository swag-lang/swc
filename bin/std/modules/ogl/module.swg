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
    cfg.genDoc.outputExtension = ".php"
    cfg.genDoc.css             = "css/style.css"
    cfg.genDoc.startHead       = "<?php include('common/start-head.php'); ?>"
    cfg.genDoc.endHead         = "<?php include('common/end-head.php'); ?>"
    cfg.genDoc.startBody       = "<?php include('common/start-body.php'); ?>"
}
