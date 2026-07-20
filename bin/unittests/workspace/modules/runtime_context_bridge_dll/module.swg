
#import("runtime_context_base_static", link: "static-library")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "RuntimeCtxDll"
    cfg.backendKind = .SharedLibrary
}
