
#import("api_export_provider")
#import("api_static_provider")
#import("runtime_context_bridge_dll")
#import("runtime_context_base_static")
#import("runtime_context_direct_static")
#import("core", location: "swag@std")
// Core also imports its native ABI module; this diamond guards global deduplication.
#static if #os == Swag.TargetOs.Windows
{
    #import("win32", location: "swag@std")
}
#static if #os == Swag.TargetOs.Linux
{
    #import("linux", location: "swag@std")
}
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleNamespace   = "ConsumerExe"
    cfg.backendKind       = .Executable
    cfg.genDoc.kind       = .Api
    cfg.genDoc.outputName = "workspace.consumer"
}
