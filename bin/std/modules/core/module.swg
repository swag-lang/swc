// The 'Std.core' module contains basic types and algorithms.
// It is the base of all other modules of the standard 'Std' workspace.
//
// You will find collections like [[Array]] or [[HashTable]], a dynamic [[String]] and so on.
#static if #os == Swag.TargetOs.Windows
{
    #import("win32")
    #import("xinput")
}

#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Core"
    cfg.backendKind     = .SharedLibrary
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/core"

    cfg.genDoc.kind            = .Api
    cfg.genDoc.outputName      = "std.core"
    cfg.genDoc.icon            = "favicon.ico"
    cfg.genDoc.titleContent    = "Swag Std.Core"
    cfg.genDoc.css             = "css/style.css"
}
