#import("artifact_name_provider", link: "static-library")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace = "ArtifactConsumer"
    cfg.backendKind = .Executable
}
