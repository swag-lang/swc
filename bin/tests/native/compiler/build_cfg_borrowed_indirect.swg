#run
{
    let cfg = dref @compiler.getBuildCfg()
    @assert(cfg.backendKind == .Executable or cfg.backendKind == .SharedLibrary or cfg.backendKind == .StaticLibrary)
}

#test
{
    @assert(true)
}
