#import("value_borrow_library", link: "shared-library")
#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.moduleNamespace = "BorrowConsumer"
    cfg.backendKind     = .Executable
}
