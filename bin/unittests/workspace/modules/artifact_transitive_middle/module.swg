#import("artifact_transitive_leaf")
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.backendKind         = .None
    cfg.moduleNamespace     = "TransitiveMiddle"
}
