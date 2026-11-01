#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Closing the information sheet gives the tools the page width back, including after a resize.
#test
{
    var host: Testing.HeadlessHost
    host.setup(880, 420)
    registerAppStrings(&host.app.resources)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let explorer = Explorer.create(window.documentPanel, window)
    window.explorer       = explorer
    window.explorerActive = true
    explorer.entries.add({name: "Films", path: "C:/Films", directory: true, attempted: true})
    explorer.fill()
    explorer.show()
    window.applyLayout()

    let line     = unwrap explorer.tools.parent
    let fullRight = line.clientRect().right()
    explorer.showInformation()
    Swag.assert(explorer.padding.z > 0 and line.clientRect().right() < fullRight)
    window.closeInformation()
    Swag.assert(explorer.padding.z == 0 and not window.infoSheet.isLocallyVisible())
    Swag.assert(Math.abs(explorer.tools.position.right() - line.clientRect().right()) < 0.5)

    window.resize(680, 420)
    window.applyLayout()
    Swag.assert(Math.abs(explorer.tools.position.right() - line.clientRect().right()) < 0.5)
}
