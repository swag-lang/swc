#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.moduleVersion  = 1
    cfg.moduleRevision = 0
    cfg.moduleBuildNum = 0
    cfg.backendKind    = .Executable

    cfg.genDoc.kind            = .Pages
    cfg.genDoc.titleContent    = "Swag"
    cfg.genDoc.css             = "css/style.css"
    cfg.genDoc.icon            = "favicon.ico"
    cfg.genDoc.morePages       = "../../../examples/scripts/flappy.swgs"
}
