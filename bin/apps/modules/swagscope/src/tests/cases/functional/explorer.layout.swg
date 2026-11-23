#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// The sheet leaves the Explorer tools at full width, including after a resize.
#test
{
    var host: Testing.HeadlessHost
    host.setup(880, 420)
    registerAppStrings(&host.app.resources)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let explorer = Explorer.create(window.documentPanel, window)
    window.explorer       = explorer
    window.explorerActive = true
    explorer.entries.add({name: "Films", path: "C:/Films", directory: true, attempted: true})
    explorer.fill()
    explorer.show()
    window.applyLayout()

    let line      = unwrap explorer.tools.parent
    let fullRight = line.clientRect().right()
    explorer.showInformation()
    Swag.require(window.infoSheet.isLocallyVisible() and line.clientRect().right() == fullRight)
    window.closeInformation()
    Swag.require(line.clientRect().right() == fullRight and not window.infoSheet.isLocallyVisible())
    Swag.require(Math.abs(explorer.tools.position.right() - line.clientRect().right()) < 0.5)

    window.resize(680, 420)
    window.applyLayout()
    Swag.require(Math.abs(explorer.tools.position.right() - line.clientRect().right()) < 0.5)
}

// The sheet keeps its top margin below the filter row, including a borderless explorer.
#test
{
    for language, index in [ReferenceLanguage, "fr"]
    {
        var host: Testing.HeadlessHost
        host.setup(960, 680, index == 0 ? 1.0 : 1.5)
        shipFrame(&host)
        registerAppStrings(&host.app.resources)
        expect host.app.setLanguage(language)
        defer discard catch host.app.setLanguage(ReferenceLanguage)
        let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        let explorer = Explorer.create(window.documentPanel, window)
        window.explorer       = explorer
        window.explorerActive = true
        explorer.entries.add({name: "Films", path: "C:/Films", directory: true, attempted: true})
        explorer.fill()
        explorer.show()
        explorer.showInformation()
        for width in [960.0'f32, ViewerWindow.MinWidth]
        {
            window.resize(width, 680)
            window.applyLayout()
            let sheet = window.infoSheet.surfaceRect()
            let inset = window.themeMetrics().floating_Inset
            Swag.require(sheet.y == explorer.tools.surfaceRect().bottom() + inset)
            Swag.require(sheet.y == window.searchGroup.surfaceRect().bottom() + inset)
            Swag.require(sheet.bottom() == window.documentPanel.surfaceRect().bottom() - inset)
        }

        let viewport = host.surface.position
        window.setFullScreen(true)
        host.surface.showNormalAt(viewport)
        window.applyLayout()
        let sheet = window.infoSheet.surfaceRect()
        Swag.require(sheet.y == window.searchGroup.surfaceRect().bottom() + window.themeMetrics().floating_Inset)
    }
}
