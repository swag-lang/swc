#import("value_borrow_provider")
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "BorrowConsumer"
    cfg.backendKind     = .Executable
}
