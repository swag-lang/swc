#global internal

#test
{
    const Cfg = #run dref @compiler.getBuildCfg()
    #assert((#cfg == "fast-debug" ? Cfg.backendOptimize == Swag.BuildCfgBackendOptim.O1 and Cfg.byteCodeOptimizeLevel == Swag.BuildCfgByteCodeOptim.O2 and Cfg.byteCodeInline : true))
}
