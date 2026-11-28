#import("value_borrow_library", link: "shared-library")
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "BorrowConsumer"
    cfg.backendKind     = .Executable
}
