#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Gui, Viewers

// The empty document opens without a chosen control; caption commands never take focus.
#test
{
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())

    Swag.require(window.focusedWindow() == null)
    Swag.require(window.outlineCaptionButton.focusPolicy == .None)
    Swag.require(window.informationCaptionButton.focusPolicy == .None)
    for child in window.infoSheet.children where child is IconButton do
        Swag.require(child.focusPolicy == .None)
    var launchers: u32
    for child in host.surfaceWnd.children
    {
        if child is Lens.Launcher as launcher
        {
            launchers += 1
            Swag.require(launcher.focusPolicy == .None)
            Swag.require(not launcher.hasFocus())
        }
    }
    Swag.require(launchers == 1)
}
