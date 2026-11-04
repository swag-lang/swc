#import("artifact_transitive_leaf", link: "shared-library")
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.backendKind = .SharedLibrary
    cfg.moduleNamespace = "TransitiveMiddle"
    cfg.publishDependencies = false
}
