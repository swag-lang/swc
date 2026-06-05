#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "ApiExportPreserve"
    cfg.backendKind = .SharedLibrary
}
