#run
{
    let itf = @compiler
    let cfg = itf.getBuildCfg()!
    cfg.moduleVersion  = 1
    cfg.moduleRevision = 0
    cfg.moduleBuildNum = 0
    cfg.backendKind    = .Executable

    cfg.genDoc.kind              = .Examples
    cfg.genDoc.titleContent      = "Swag Language Reference"
    cfg.genDoc.css               = "css/style.css"
    cfg.genDoc.icon              = "favicon.svg"
    cfg.genDoc.outputName        = "language"
    cfg.genDoc.quoteTitleExample = "Result"
}
