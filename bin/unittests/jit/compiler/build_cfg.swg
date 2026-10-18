#global private

#test
{
    const Cfg = #run Swag.compiler().getBuildCfg()![]
    #assert(#typeof(Cfg.backend.optimLevel) == Swag.Build.BackendOptimLevel)
    #assert(Cfg.backend.debugInfo == false)
    #assert(Cfg.backend.enableExceptions == true)
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
    #assert(Cfg.registeredConfigs == "devmode|release")
    #assert(Cfg.name == null)
    #assert(Cfg.outDir == "" or Cfg.outDir != "")
    #assert(Cfg.workDir == "" or Cfg.workDir != "")
}

#test
{
    const Cfg = #run Swag.compiler().getBuildCfg()![]
    var bad: s32 = Cfg.backend.enableExceptions     // swc-expected-error {{sema_err_cannot_cast}}
}
