#global internal

#test
{
    const Cfg = #run dref @compiler.getBuildCfg()
    #if #cfg == "fast-compile"
    {
        #assert(Cfg.backend.optimizeLevel == Swag.BuildCfgBackendOptim.O0)
    }
    #if #cfg == "debug"
    {
        #assert(Cfg.backend.optimizeLevel == Swag.BuildCfgBackendOptim.O0)
    }
    #if #cfg == "fast-debug"
    {
        #assert(Cfg.backend.optimizeLevel == Swag.BuildCfgBackendOptim.O1)
    }
    #if #cfg == "release"
    {
        #assert(Cfg.backend.optimizeLevel == Swag.BuildCfgBackendOptim.O3)
    }
}
