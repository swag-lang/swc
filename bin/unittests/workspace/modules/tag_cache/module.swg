#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.backendKind = .Executable
}
