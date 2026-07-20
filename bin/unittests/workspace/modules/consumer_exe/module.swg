#global #[Swag.ExplicitNullability]

#import("api_export_provider")
#import("api_static_provider", link: "static-library")
#import("runtime_context_bridge_dll")
#import("runtime_context_base_static", link: "static-library")
#import("runtime_context_direct_static", link: "static-library")
#run
{
    // Keep the workspace rooted at an executable so we validate direct exe -> dll usage.
    let cfg = @compiler.getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "ConsumerExe"
    cfg.backendKind = .Executable
}
