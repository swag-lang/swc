#import("borrow_field_provider", link: "shared-library")
#import("core", location: "swag@std")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "BorrowFieldConsumer"
    cfg.backendKind = .Executable
}
