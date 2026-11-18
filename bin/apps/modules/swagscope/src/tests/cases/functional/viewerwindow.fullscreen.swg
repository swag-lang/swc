#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// The window owns full screen even before a viewer is open, without taking keyboard focus.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    host.surface.updateFlags(SurfaceFlags.StandardWindow | SurfaceFlags.NoShadow)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let button = window.fullScreenCaptionButton
    Swag.require(button.isVisible() and button.focusPolicy == .None)
    Swag.require(button.id == ViewerCommands.FullScreen)
    Swag.require(button.surfaceRect().right() <= host.surfaceWnd.minimizeBtn!.surfaceRect().x)

    host.clickWnd(button)
    Swag.require(window.fullScreen and not button.isLocallyVisible())
    host.keyPress(.Escape)
    Swag.require(not window.fullScreen and button.isVisible())
    host.keyPress(.F11)
    Swag.require(window.fullScreen)
    host.keyPress(.F11)
    Swag.require(not window.fullScreen and button.isVisible())
}

// Folder and document views expose the same window action throughout their lifecycle.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("comprehensive.txt"), true)
    let button = window.fullScreenCaptionButton
    Swag.require(button.isVisible())
    host.clickWnd(button)
    Swag.require(window.fullScreen)
    host.keyPress(.Escape)

    window.onlineMovies = false
    window.onlineMusic  = false
    window.openExplorer(scopeTestDataDirectory())
    let explorer = unwrap window.explorer
    explorer.setMode(.Names)
    completeExplorer(&host, explorer)
    Swag.require(window.isExploring() and button.isVisible())
    host.clickWnd(button)
    Swag.require(window.fullScreen)
    host.keyPress(.Escape)
    Swag.require(window.isExploring() and not window.fullScreen and button.isVisible())
}
