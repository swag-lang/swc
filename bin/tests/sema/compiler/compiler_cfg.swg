#global internal

#test
{
    const Cfg = #run dref @compiler.getBuildCfg()
    #assert(Cfg.backend.optimize == true or Cfg.backend.optimize == false)
    #assert(Cfg.backend.optimizeForSize == true or Cfg.backend.optimizeForSize == false)
}
