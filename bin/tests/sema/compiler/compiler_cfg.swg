#global fileprivate

#test
{
    const Cfg = #run dref @compiler.getBuildCfg()
    #assert(Cfg.backend.optimize == true or Cfg.backend.optimize == false)
    #assert(Cfg.jitEnableSehUnwind == true or Cfg.jitEnableSehUnwind == false)
}

#test
{
    const Cfg = #run dref @compiler.getBuildCfg()
    var bad: s32 = Cfg.jitEnableSehUnwind // swc-expected-error {{sema_err_cannot_cast}}
}
