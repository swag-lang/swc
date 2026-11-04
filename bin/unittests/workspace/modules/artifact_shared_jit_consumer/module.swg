#import("artifact_shared_provider", link: "shared-library")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "SharedArtifactJitConsumer"
    cfg.backendKind = .Executable
}
