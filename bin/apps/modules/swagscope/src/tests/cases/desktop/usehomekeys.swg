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
    Swag.require(window.lens.query().count == 0, "the opening shortcut typed into the lens")
    input.shortcut(.Escape, .None)
    Swag.require(not window.lens.isOpen(), "the lens did not close after Escape")
    input.shortcut(.F11, .None)
    Swag.require(window.fullScreen)
}
