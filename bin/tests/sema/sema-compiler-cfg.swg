#global internal

#test
{
    const Cfg = #run dref @compiler.getBuildCfg()
    #if #cfg == "fast-compile"
    {
        #assert(Cfg.backend.optimizeLevel == Swag.BuildCfgBackendOptim.O0 and Cfg.byteCodeOptimizeLevel == Swag.BuildCfgByteCodeOptim.O0 and !Cfg.byteCodeInline)
    }
    #if #cfg == "debug"
    {
        #assert(Cfg.backend.optimizeLevel == Swag.BuildCfgBackendOptim.O0 and Cfg.byteCodeOptimizeLevel == Swag.BuildCfgByteCodeOptim.O1 and !Cfg.byteCodeInline)
    }
    #if #cfg == "fast-debug"
    {
        #assert(Cfg.backend.optimizeLevel == Swag.BuildCfgBackendOptim.O1 and Cfg.byteCodeOptimizeLevel == Swag.BuildCfgByteCodeOptim.O2 and Cfg.byteCodeInline)
    }
    #if #cfg == "release"
    {
        #assert(Cfg.backend.optimizeLevel == Swag.BuildCfgBackendOptim.O3 and Cfg.byteCodeOptimizeLevel == Swag.BuildCfgByteCodeOptim.O3 and Cfg.byteCodeInline)
    }
}
