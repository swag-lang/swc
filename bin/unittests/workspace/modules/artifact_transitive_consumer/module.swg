#import("artifact_transitive_middle")
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.backendKind         = .Executable
}
