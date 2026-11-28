#import("source_dependency_provider")

#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace     = "SourceDependencyConsumer"
    cfg.backendKind         = .Executable
}
