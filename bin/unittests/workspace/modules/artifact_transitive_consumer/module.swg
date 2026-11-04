#import("artifact_transitive_middle", link: "shared-library")
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.backendKind = .Executable
    cfg.publishDependencies = false
}
