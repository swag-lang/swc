#global fileprivate

#test
{
    const Cfg = #run dref @compiler.getBuildCfg()
    #assert(Cfg.backend.optimize == true or Cfg.backend.optimize == false)
    #assert(Cfg.backend.debugInfo == true)
    #assert(Cfg.backend.enableExceptions == true)
}

#test
{
    const Cfg = #run dref @compiler.getBuildCfg()
    var bad: s32 = Cfg.backend.enableExceptions // swc-expected-error {{sema_err_cannot_cast}}
}
