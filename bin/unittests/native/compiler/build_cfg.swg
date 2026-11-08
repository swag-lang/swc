#global private
const Cfg = #run Swag.compiler().getBuildCfg()![]

#assert(#typeof(Cfg) == Swag.Build.Config)
#assert(#typeof(Cfg.backend.optimLevel) == Swag.Build.BackendOptimLevel)
#assert(Cfg.backend.debugInfo == false)
#assert(#typeof(Cfg.backend.math) == Swag.Build.BackendMath)
#assert(Cfg.backend.math.unsafe == false)
#assert(Cfg.backend.math.approxFunc == false)
#assert(#typeof(Cfg.backend.optimizer) == Swag.Build.Optimizer)
#assert(Cfg.backend.optimizer.iterations.preRaSweeps == 0)
#assert(Cfg.backend.optimizer.unroll.memoryBytes == 0)
#assert(Cfg.backend.optimizer.vectorization.maxTreeDepth == 0)
#assert(#typeof(Cfg.backend.enableExceptions) == bool)
#static if #hastag("Swag.AllocatorDiagnostics")
{
    #assert(#typeof(Cfg.allocatorCaptureStack) == bool)
    #assert(#typeof(Cfg.allocatorLeaks) == bool)
    #assert(#typeof(Cfg.allocatorTrackAllocations) == bool)
    #assert(#typeof(Cfg.allocatorElectricMode) == bool)
    #assert(#typeof(Cfg.allocatorFillMemory) == bool)
}
else
{
    #assert(not #defined(Cfg.allocatorCaptureStack))
    #assert(not #defined(Cfg.allocatorLeaks))
    #assert(not #defined(Cfg.allocatorTrackAllocations))
    #assert(not #defined(Cfg.allocatorElectricMode))
    #assert(not #defined(Cfg.allocatorFillMemory))
}
#assert(Cfg.registeredConfigs == "devmode|release|release-safe")
#assert(Cfg.backend.optimLevel == (#cfg == "devmode" ? Swag.Build.BackendOptimLevel.O1 : Swag.Build.BackendOptimLevel.O2))
#assert(#safety(Swag.SafetyWhat.Expect) == (#cfg != "release"))
#assert(#safety(Swag.SafetyWhat.Null) == (#cfg != "release"))
#static if #cfg == "release-safe"
{
    #assert(not Cfg.backend.math.noNaN and not Cfg.backend.math.noInf)
}
#assert(Cfg.backendKind == Swag.Build.BackendKind.Executable or
        Cfg.backendKind == Swag.Build.BackendKind.SharedLibrary or
        Cfg.backendKind == Swag.Build.BackendKind.StaticLibrary)
#assert(Cfg.backendSubKind == Swag.Build.BackendSubKind.Default or
        Cfg.backendSubKind == Swag.Build.BackendSubKind.Console)

// BuildCfg fields are valid at runtime
#test
{
    Swag.require(Cfg.registeredConfigs == "devmode|release|release-safe")
    Swag.require(Cfg.backendKind != Swag.Build.BackendKind.None)
    Swag.require(Cfg.moduleVersion >= 0'u32)
    Swag.require(Cfg.moduleRevision >= 0'u32)
    Swag.require(Cfg.moduleBuildNum >= 0'u32)
}

#static if #cfg == "release-safe"
{
    struct GuardedLateSlot { late value: *s32 }

    #[Swag.NoInline]
    func readUninitializedSlot(shouldInitialize: bool)->s32
    {
        var slot: GuardedLateSlot
        var value: s32 = 42
        if shouldInitialize do slot.value = &value
        return slot.value[]
    }

    #test
    {
        var absent: *s32? = null
        let missing = Swag.catchPanic(func|&absent|() { discard unwrap absent })
        Swag.require(missing.raised)

        let uninitialized = Swag.catchPanic(func() { discard readUninitializedSlot(false) })
        Swag.require(uninitialized.raised)
    }
}
