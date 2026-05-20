#import("ctxbase", link: "static-library")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "Shrd"
    cfg.backendKind = .SharedLibrary
}
