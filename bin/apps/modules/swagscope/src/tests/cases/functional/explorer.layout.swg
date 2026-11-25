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
    Swag.require(host.surfaceWnd.titleHidden and host.surfaceWnd.name == workspace.sceneName(unwrap workspace.scene()))

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
    let button = document.readingLine.close
    Swag.require(button.isVisible() and not document.cellCaption.isVisible())
    let close = button.surfaceRect()
    Swag.require(close.right() == document.readingLine.surfaceRect().right())
    Swag.require(close.y >= explorer.grid.surfaceRect().bottom())
    Swag.require(host.surfaceWnd.windowAt(close.horzCenter(), close.vertCenter()) == button)
    host.clickWnd(button)
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
    Swag.require(explorer.address.isVisible() and document.readingLine.close.isVisible())
    host.clickWnd(document.readingLine.close)
    Swag.require(workspace.scenes.isEmpty() and workspace.primary.home.isVisible())
}

// Folder controls remain reachable at the divider's narrow limit and return when space allows.
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, width: ViewerWindow.MinWidth)
    defer host.shutdown()
    let file = scopeTestDataPath("sample.cpp")
    workspace.openScene([file, scopeTestDataPath("viewer.png")], .SideBySide)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    let document = workspace.activeDocument()
    document.openExplorer(unwrap Path.directoryName(file))
    let explorer = unwrap document.explorer
    completeExplorer(&host, explorer)
    scene.split = 0.18
    workspace.layoutScene()
    Swag.require(not explorer.kindMenu.isVisible() and not explorer.sortMenu.isVisible())
    Swag.require(not document.searchOptionsButton.isVisible() and explorer.modeMenu.isVisible())
    Swag.require(document.searchBox.position.width >= 60, Format.toString("cell % line % tools % field %", document.position, explorer.tools.parent!.position, explorer.tools.position, document.searchBox.position))
    Swag.require(document.documentHost.position.width == document.clientRect().width)
    let field = document.searchBox.surfaceRect()
    Swag.require(field.right() <= explorer.modeMenu.surfaceRect().x)
    let reading = document.readingLine
    Swag.require(reading.close.isVisible() and reading.close.position.right() == reading.clientRect().right())
    Swag.require(reading.details.position.right() <= reading.close.position.x)
    explorer.setMode(.Details)
    explorer.list.setColumnWidth(0, 284)
    explorer.setMode(.Names)
    Swag.require(explorer.list.scrollWnd.flags.has(.DisableHorizontal))
    Swag.require(explorer.list.header.itemWidthForColumn(0) == explorer.list.listView.paddedClientRect().width)
    explorer.setMode(.Details)
    Swag.require(explorer.list.header.itemWidthForColumn(0) == 284 and not explorer.list.scrollWnd.flags.has(.DisableHorizontal))
    host.clickWnd(document.searchBox)
    Swag.require(document.searchBox.hasFocus())
    host.keyPress(.F6)
    Swag.require(not scene.maximized and document.searchBox.hasFocus())
    host.keyPress(.F)
    host.sendRune(.F, 'f'rune)
    Swag.require(not scene.maximized and document.searchBox.hasFocus() and document.searchBox.text() == "f")
    document.searchBox.setText("")
    let sheet = OptionSheet.View.create(explorer.modeMenu, func|explorer|(page) { explorer.describeViewOptions(page) }, owner: explorer)
    sheet.refresh()
    Swag.require(sheet.activateRow(appStrings().explore_FilterByType))
    Swag.require(sheet.activateRow(appStrings().explore_FilterImages))
    Swag.require(explorer.kindFilter == .Images)
    sheet.destroy()
    workspace.closeView(1)
    Swag.require(explorer.kindMenu.isVisible() and explorer.sortMenu.isVisible() and document.searchOptionsButton.isVisible())
}

// With two scenes the folder address belongs to the page, leaving each tab clickable.
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    let file = scopeTestDataPath("sample.cpp")
    workspace.openDocument(file)
    openViews(&host, workspace)
    workspace.openDocument(scopeTestDataPath("viewer.srt"))
    openViews(&host, workspace)
    let document = workspace.activeDocument()
    document.openExplorer(unwrap Path.directoryName(file))
    let explorer = unwrap document.explorer
    completeExplorer(&host, explorer)
    let tabs = workspace.tabs
    Swag.require(tabs.isVisible() and explorer.address.surfaceRect().y >= tabs.surfaceRect().bottom())
    workspace.closeScene(0)
    Swag.require(not tabs.isVisible() and explorer.address.surfaceRect().bottom() <= workspace.stripInset())
}
