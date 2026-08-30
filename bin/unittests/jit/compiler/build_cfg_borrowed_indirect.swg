#run
{
    let cfg = Swag.compiler().getBuildCfg()![]
    Swag.assert(cfg.backendKind == .Executable or cfg.backendKind == .SharedLibrary or cfg.backendKind == .StaticLibrary)
}

#test
{
    Swag.assert(true)
}
