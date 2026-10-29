#run
{
    let itf = Swag.compiler()
    let cfg = unwrap itf.getBuildCfg()
    cfg.moduleVersion  = 1
    cfg.moduleRevision = 0
    cfg.moduleBuildNum = 0
    cfg.backendKind    = .StaticLibrary

    cfg.genDoc.kind         = .Pages
    cfg.genDoc.titleContent = "Swag"
    cfg.genDoc.css          = "css/style.css"
    cfg.genDoc.icon         = "favicon.svg"
    cfg.genDoc.morePages    = "../../../examples/scripts/flappy.swgs"
}
