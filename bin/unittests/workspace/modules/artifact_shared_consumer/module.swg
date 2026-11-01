#import("artifact_shared_provider", link: "shared-library")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "SharedArtifactConsumer"
    cfg.backendKind = .Executable
    cfg.publishDependencies = false
}
