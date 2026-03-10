#global fileprivate

#test
{
    const cfg = #run dref @compiler.getBuildCfg()
    #assert(cfg.backend.debugInfo == true)
    #assert(cfg.backend.enableExceptions == true)
    #assert(cfg.backendKind == Swag.BuildCfgBackendKind.Executable or cfg.backendKind == Swag.BuildCfgBackendKind.Library or cfg.backendKind == Swag.BuildCfgBackendKind.Export)
}
