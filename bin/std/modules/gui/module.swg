/*
GUI builds native desktop interfaces from composable windows, controls, dialogs,
themes, actions, and Pixel drawing.

An [[Gui.Application]] owns surfaces and drives the event loop. Each
[[Gui.Surface]] has a root [[Gui.Wnd]]; controls form a flatly documented API and
are connected at runtime through parent links, event hooks, signals, docking, and
layout constraints.

## Create a window

```swag
using Core, Gui

var app: Application

#main
{
    let surface = notnull (try app.createSurface(
        100, 100, 640, 420, SurfaceFlags.OverlappedWindow))
    surface.setTitle("My application")

    let button = PushButton.create(surface.getView(), "Continue")
    button.dockStyle = .CenterKeepSizeVert

    surface.show()
    return app.run()
}
```

Coordinates and sizes are logical pixels. Windows are owned by their application;
use [[Gui.Wnd.destroy]] for deferred destruction during event dispatch.
*/

#import("pixel")

#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.moduleVersion     = #swcversion
    cfg.moduleRevision    = #swcrevision
    cfg.moduleBuildNum    = #swcbuildnum
    cfg.moduleNamespace   = "Gui"
    cfg.backendKind       = .SharedLibrary
    cfg.ignoreInWorkspace = false
    cfg.repoPath          = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/gui"

    cfg.genDoc.kind         = .Api
    cfg.genDoc.outputName   = "std.gui"
    cfg.genDoc.titleContent = "GUI"
    cfg.genDoc.titleToc     = "GUI documentation"
    cfg.genDoc.icon         = "favicon.svg"
    cfg.genDoc.css          = "css/style.css"
}
