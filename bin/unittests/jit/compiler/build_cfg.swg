#global private

#test
{
    const Cfg = #run dref @compiler.getBuildCfg()
    #assert(Cfg.backend.optimize == true or Cfg.backend.optimize == false)
    #assert(Cfg.backend.debugInfo == true)
    #assert(Cfg.backend.enableExceptions == true)
    #assert(#typeof(Cfg.allocatorCaptureStack) == bool)
    #assert(#typeof(Cfg.allocatorLeaks) == bool)
    #assert(#typeof(Cfg.allocatorTrackAllocations) == bool)
    #assert(#typeof(Cfg.allocatorElectricMode) == bool)
    #assert(#typeof(Cfg.allocatorFillMemory) == bool)
    #assert(Cfg.registeredConfigs == "fast-compile|debug|fast-debug|release")
    #assert(Cfg.name == null)
    #assert(Cfg.outDir == "" or Cfg.outDir != "")
    #assert(Cfg.workDir == "" or Cfg.workDir != "")
}

#test
{
    const Cfg = #run dref @compiler.getBuildCfg()
    var bad: s32 = Cfg.backend.enableExceptions     // swc-expected-error {{sema_err_cannot_cast}}
}
