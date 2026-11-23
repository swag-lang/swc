#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// The launch surface receives global keys before any control has been clicked.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    let state = Testing.tempFilePath("scope-home-keys-", ".scc")
    defer catch File.delete(state)
    var app: Application
    app.setStatePath(state)
    registerAppStrings(&app.resources)
    let surface   = expect app.createSurface(40, 40, 1000, 640, surfaceId: "scope-home-keys")
    let workspace = ViewerWorkspace.create(surface.wnd, createViewerPluginRegistry())
    let window    = workspace.primary
    surface.show()
    defer surface.destroy()

    var input = Testing.DesktopInput.create(&app, surface)
    Swag.require(window.home.isLocallyVisible() and window.focusedWindow() == null)
    input.shortcut(.Space, .Control)
    Swag.require(window.lens.isOpen())
    input.shortcut(.Escape, .None)
    input.shortcut(.F11, .None)
    Swag.require(window.fullScreen)
}
