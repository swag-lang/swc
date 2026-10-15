#global private
const Cfg = #run Swag.compiler().getBuildCfg()![]

#assert(#typeof(Cfg) == Swag.Build.Config)
#assert(#typeof(Cfg.backend.optimLevel) == Swag.Build.BackendOptimLevel)
#assert(Cfg.backend.debugInfo == false)
#assert(#typeof(Cfg.backend.enableExceptions) == bool)
#assert(#typeof(Cfg.allocatorCaptureStack) == bool)
#assert(#typeof(Cfg.allocatorLeaks) == bool)
#assert(#typeof(Cfg.allocatorTrackAllocations) == bool)
#assert(#typeof(Cfg.allocatorElectricMode) == bool)
#assert(#typeof(Cfg.allocatorFillMemory) == bool)
#assert(Cfg.registeredConfigs == "devmode|release")
#assert(Cfg.backendKind == Swag.Build.BackendKind.Executable or
        Cfg.backendKind == Swag.Build.BackendKind.SharedLibrary or
        Cfg.backendKind == Swag.Build.BackendKind.StaticLibrary)
#assert(Cfg.backendSubKind == Swag.Build.BackendSubKind.Default or
        Cfg.backendSubKind == Swag.Build.BackendSubKind.Console)

// BuildCfg fields are valid at runtime
#test
{
    Swag.assert(Cfg.registeredConfigs == "devmode|release")
    Swag.assert(Cfg.backendKind != Swag.Build.BackendKind.None)
    Swag.assert(Cfg.moduleVersion >= 0'u32)
    Swag.assert(Cfg.moduleRevision >= 0'u32)
    Swag.assert(Cfg.moduleBuildNum >= 0'u32)
}
