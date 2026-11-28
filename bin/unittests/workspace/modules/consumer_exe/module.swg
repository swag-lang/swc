
#import("api_export_provider")
#import("api_static_provider", link: "static-library")
// Pinned: an executable links its dependencies in by default, and this module is what keeps the
// exe -> dll path covered. Asking for one shared library asks for all of them, so every import
// below resolves to a DLL too.
#import("runtime_context_bridge_dll", link: "shared-library")
#import("runtime_context_base_static", link: "static-library")
#import("runtime_context_direct_static", link: "static-library")
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
    // Keep the workspace rooted at an executable so we validate direct exe -> dll usage.
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.embeddedImports   = true
    cfg.moduleNamespace   = "ConsumerExe"
    cfg.backendKind       = .Executable
    cfg.genDoc.kind       = .Api
    cfg.genDoc.outputName = "workspace.consumer"
}
