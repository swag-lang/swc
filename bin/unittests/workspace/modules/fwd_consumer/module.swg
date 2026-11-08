#import("fwd_provider")
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "FwdConsumer"
    cfg.backendKind = .Executable
}
