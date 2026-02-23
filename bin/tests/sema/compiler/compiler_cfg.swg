#global internal

#test
{
    const Cfg = #run dref @compiler.getBuildCfg()
    #assert(Cfg.backend.optimizeLevel == Swag.BuildCfgBackendOptim.O0 or
            Cfg.backend.optimizeLevel == Swag.BuildCfgBackendOptim.O1 or
            Cfg.backend.optimizeLevel == Swag.BuildCfgBackendOptim.O2 or
            Cfg.backend.optimizeLevel == Swag.BuildCfgBackendOptim.O3 or
            Cfg.backend.optimizeLevel == Swag.BuildCfgBackendOptim.Os or
            Cfg.backend.optimizeLevel == Swag.BuildCfgBackendOptim.Oz)
}
