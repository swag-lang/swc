#import("artifact_name_provider")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "ArtifactConsumer"
    cfg.backendKind     = .Executable
}
