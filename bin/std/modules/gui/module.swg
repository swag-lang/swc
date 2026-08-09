/*
GUI builds native desktop interfaces from composable windows, controls, dialogs,
themes, actions, password-safe input, and Pixel drawing.

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
    let surface = (try app.createSurface(
        100, 100, 640, 420, SurfaceFlags.StandardWindow))!
    surface.setTitle("My application")

    let button = PushButton.create(surface.view(), "Continue")
    button.dockStyle = .CenterKeepSizeVert

    surface.show()
    return app.run()
}
```

Coordinates and sizes are logical pixels. Windows are owned by their application;
use [[Gui.Wnd.destroy]] for deferred destruction during event dispatch.

Finite transitions use the application-owned [[Gui.Animator]]. Typed tracks can be
retargeted by [[Gui.AnimationChannel]], grouped in parallel or sequence, and are
cancelled automatically when their target is hidden or destroyed. See
`help/08-animation.md` for the motion and presentation contract.
*/

#import("pixel")

#run
{
    let itf = @compiler
    let cfg = itf.getBuildCfg()!
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
