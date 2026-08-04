#run
{
    let itf = @compiler
    let cfg = itf.getBuildCfg()!
    cfg.backendKind = .Executable

    cfg.genDoc.kind         = .Pages
    cfg.genDoc.titleContent = "Swag"
    cfg.genDoc.css          = "css/style.css"
    cfg.genDoc.theme        = .Dark
}
