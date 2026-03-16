#global fileprivate // swc-option suite-test

const Cfg = #run dref @compiler.getBuildCfg()

#assert(#typeof(Cfg) == Swag.BuildCfg)
#assert(#typeof(Cfg.backend.optimize) == bool)
#assert(#typeof(Cfg.backend.debugInfo) == bool)
#assert(#typeof(Cfg.backend.enableExceptions) == bool)
#assert(Cfg.registeredConfigs == "fast-compile|debug|fast-debug|release")
#assert(Cfg.backendKind == Swag.BuildCfgBackendKind.Executable or
        Cfg.backendKind == Swag.BuildCfgBackendKind.Library or
        Cfg.backendKind == Swag.BuildCfgBackendKind.Export)
#assert(Cfg.backendSubKind == Swag.BuildCfgBackendSubKind.Default or
        Cfg.backendSubKind == Swag.BuildCfgBackendSubKind.Console)

#test
{
    @assert(Cfg.registeredConfigs == "fast-compile|debug|fast-debug|release")
    @assert(Cfg.backendKind != Swag.BuildCfgBackendKind.None)
    @assert(Cfg.moduleVersion >= 0'u32)
    @assert(Cfg.moduleRevision >= 0'u32)
    @assert(Cfg.moduleBuildNum >= 0'u32)
}
