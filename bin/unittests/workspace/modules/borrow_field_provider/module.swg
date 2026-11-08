#import("core", location: "swag@std")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "BorrowFieldProvider"
    cfg.backendKind = .SharedLibrary
}
