#run
{
    let cfg = Swag.compiler().getBuildCfg()![]
    Swag.assert(cfg.backendKind == .Executable)
}

#test
{
    Swag.require(true)
}
