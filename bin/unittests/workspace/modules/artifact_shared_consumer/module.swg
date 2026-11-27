#import("artifact_shared_provider")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace     = "SharedArtifactConsumer"
    cfg.backendKind         = .Executable
}
