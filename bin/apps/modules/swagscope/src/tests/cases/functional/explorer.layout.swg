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

// The trailing cell's folder path lives inside its header, above its filter and file list.
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    let left = scopeTestDataPath("comprehensive.txt")
    let right = scopeTestDataPath("sample.cpp")
    workspace.openScene([left, right], .SideBySide)
    openViews(&host, workspace)
    workspace.selectView(1)

    let document = workspace.activeDocument()
    document.openExplorer(unwrap Path.directoryName(right))
    let explorer = unwrap document.explorer
    completeExplorer(&host, explorer)
    host.finishAnimations()
    let address = explorer.address
    let bounds  = address.surfaceRect()
    Swag.require(address.isLocallyVisible() and document.surfaceRect().contains(bounds.center()))
    Swag.require(bounds.bottom() < document.searchGroup.surfaceRect().y)

    let crumb = address.breadcrumb
    let point = crumb.localToSurface(crumb.items.backPtr().bodyRect.center())
    Swag.require(host.surfaceWnd.windowAt(point.x, point.y) == crumb)
    var screen = point
    host.surface.surfaceToScreen(&screen)
    host.click(screen)
    Swag.require(address.edit.isLocallyVisible() and address.edit.hasFocus())

    Swag.require(Path.equals(workspace.scene()!.views[1].path, explorer.requested))
    Swag.require(not workspace.hasSceneTransport() and not workspace.canPlayScene())
    var pointer = explorer.grid.surfaceRect().center()
    host.surface.surfaceToScreen(&pointer)
    host.moveMouse(pointer)
    host.finishAnimations()
    Swag.require(document.cellCaptionClose.isVisible() and not document.cellCaptionTitle.isVisible())
    let close = document.cellCaptionClose.surfaceRect()
    Swag.require(close.x >= address.surfaceRect().right())
    Swag.require(host.surfaceWnd.windowAt(close.horzCenter(), close.vertCenter()) == document.cellCaptionClose)
    host.clickWnd(document.cellCaptionClose)
    Swag.require(workspace.documentCount() == 1 and Path.equals(workspace.activeDocument().currentFile, expect Path.absolute(left)))
}

// Closing a neighbouring view keeps the folder editor usable through the transition to solo.
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    let first = scopeTestDataPath("sample.cpp")
    workspace.openScene([first, scopeTestDataPath("viewer.png")], .SideBySide)
    openViews(&host, workspace)
    let document = workspace.activeDocument()
    document.openExplorer(unwrap Path.directoryName(first))
    let explorer = unwrap document.explorer
    completeExplorer(&host, explorer)
    document.showSearch()
    Swag.require(document.searchBox.hasFocus())
    workspace.closeView(1)
    Swag.require(workspace.activeDocument() == document and document.searchBox.hasFocus())
    Swag.require(explorer.address.isVisible() and workspace.closeFileButton.isVisible())
    host.clickWnd(workspace.closeFileButton)
    Swag.require(workspace.scenes.isEmpty() and workspace.primary.home.isVisible())
}
