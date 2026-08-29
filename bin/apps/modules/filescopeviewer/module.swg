/*
FileScope Viewer defines the source-level contract between sFileScope and a file-viewer plugin.

A plugin publishes one [[FileScope.Plugin]] descriptor. Its creation callback receives only a
[[FileScope.Host]] interface: the host supplies the document parent, creates action, information,
and command groups, owns failure and progress presentation, and accepts optional search and
lifecycle callbacks. Plugin code never depends on sFileScope's window implementation.

The descriptor owns its strings and selectors for as long as it remains registered. The host owns
the document and every group created through [[FileScope.Host]], while a plugin owns resources
behind its view until its optional [[FileScope.Retire]] callback succeeds.

```swag
func createPreview(host: FileScope.Host)
{
    let view = Wnd.create'Wnd(host.contentParent(), "example.preview")
    host.attachView(view)
    host.setDetails("Preview")
}

var plugin: FileScope.Plugin
plugin.key          = "preview"
plugin.staticName   = "Preview"
plugin.icon         = &previewIcon
plugin.create       = &createPreview
plugin.smokeFixture = "preview.fixture"
plugin.selectors.add(String.from(".preview"))
```

The module is a shared library so built-in viewers and future separately built adapters can use
the same contract. Runtime discovery and a stable native entry point are deliberately separate
concerns; [[FileScope.ViewerApiVersion]] versions the contract a loader will negotiate.
*/

#import("gui", location: "swag@std")

#run
{
    let cfg = @compiler.getBuildCfg()!
    cfg.moduleVersion     = #swcversion
    cfg.moduleRevision    = #swcrevision
    cfg.moduleBuildNum    = #swcbuildnum
    cfg.moduleNamespace   = "FileScope"
    cfg.backendKind       = .SharedLibrary
    cfg.ignoreInWorkspace = false

    cfg.genDoc.kind         = .Api
    cfg.genDoc.outputName   = "apps.filescopeviewer"
    cfg.genDoc.titleContent = "FileScope Viewer"
    cfg.genDoc.titleToc     = "FileScope Viewer API"
}
