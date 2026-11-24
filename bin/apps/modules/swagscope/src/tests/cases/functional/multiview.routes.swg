#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Audio

#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()

    let first  = expect Path.absolute(scopeTestDataPath("comprehensive.txt"))
    let second = expect Path.absolute(scopeTestDataPath("sample.cpp"))
    let third  = expect Path.absolute(scopeTestDataPath("viewer.srt"))
    workspace.openDocument(first)
    openViews(&host, workspace)

    host.acceptModalFileDialog(second)
    host.shortcut(.O, .Control)
    Swag.require(host.autoHandled)
    openViews(&host, workspace)
    Swag.require(workspace.scenes.count == 2 and workspace.activeDocument().currentFile == second)

    host.acceptModalFileDialog(third)
    Swag.require(workspace.activeDocument().runCommand(SceneCommands.Beside) and host.autoHandled)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    Swag.require(workspace.scenes.count == 2 and scene.layout == .SideBySide and not scene.linked)
    Swag.require(scene.views[0].path == second and scene.views[1].path == third)

    host.keyPress(.W, .Control)
    host.acceptModalFileDialog(first)
    Swag.require(workspace.activeDocument().runCommand(SceneCommands.CompareWith) and host.autoHandled)
    openViews(&host, workspace)
    Swag.require(workspace.scene() == scene and scene.views[1].path == first and scene.compared and scene.linked)

    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    Swag.require(workspace.activeDocument().runCommand(SceneCommands.OpenGrid) and host.autoHandled)
    Swag.require(workspace.scenes.count == 2 and workspace.scene() == scene)

    let files = scopeTestDataPath("sample.cpp;viewer.srt")
    host.acceptModalFileDialog(files)
    Swag.require(workspace.activeDocument().runCommand(SceneCommands.OpenGrid) and host.autoHandled)
    openViews(&host, workspace)
    let grid = unwrap workspace.scene()
    Swag.require(workspace.scenes.count == 3 and grid.layout == .Grid2)
    Swag.require(grid.views.count == 2 and grid.views[0].path == second and grid.views[1].path == third)

    host.acceptModalFileDialog(first)
    Swag.require(workspace.activeDocument().runCommand(SceneCommands.CompareWith) and host.autoHandled)
    openViews(&host, workspace)
    Swag.require(workspace.scenes.count == 4 and workspace.documentCount() == 2)
    Swag.require(workspace.scene()!.compared and workspace.scene()!.views[0].path == second)
    Swag.require(grid.layout == .Grid2 and grid.views[0].path == second and grid.views[1].path == third)
}

// A drag follows the pointer between occupied cells. It leaves the active document alone
// until the drop, and replaces only the file in the cell it lands on.
#test
{
    let first  = expect Path.absolute(scopeTestDataPath("comprehensive.txt"))
    let second = expect Path.absolute(scopeTestDataPath("sample.cpp"))
    let third  = expect Path.absolute(scopeTestDataPath("viewer.srt"))
    let replacement = expect Path.absolute(scopeTestDataPath("viewer.txt"))
    let path = replacement.toString()

    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    workspace.openScene([first, second, third], .Grid2)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    let original = workspace.activeDocument()
    let target   = scene.views[1].document

    var left = workspace.localToSurface(workspace.viewRect(scene, 0).center())
    var right = workspace.localToSurface(workspace.viewRect(scene, 1).center())
    var empty = workspace.localToSurface(workspace.viewRect(scene, 3).center())
    host.surface.surfaceToScreen(&left)
    host.surface.surfaceToScreen(&right)
    host.surface.surfaceToScreen(&empty)
    Swag.require(host.dragFilesOver(left, [path]) == .Copy and workspace.dropView == 0)
    Swag.require(host.dragFilesOver(right, [path]) == .Copy and workspace.dropView == 1)
    Swag.require(workspace.activeDocument() == original)
    Swag.require(host.dragFilesOver(empty, [path]) == .Copy and workspace.dropView == 3)
    Swag.require(workspace.activeDocument() == original and scene.views.count == 3)
    Swag.require(scene.views[1].path == second)
    Swag.require(host.dragFilesOver(right, [path]) == .Copy and workspace.dropView == 1)
    host.cancelDrag()
    Swag.require(workspace.dropView == Swag.U64.Max and scene.views[1].path == second)

    Swag.require(host.dropFiles(right, [path]) == .Copy)
    openViews(&host, workspace)
    Swag.require(workspace.dropView == Swag.U64.Max)
    Swag.require(workspace.scenes.count == 1 and scene.layout == .Grid2 and scene.views.count == 3)
    Swag.require(scene.views[0].document == original and original.currentFile == first)
    Swag.require(scene.views[1].document == target and workspace.activeDocument().currentFile == replacement)
    Swag.require(scene.views[2].path == third)

    Swag.require(host.dropFiles(empty, [path]) == .Copy)
    openViews(&host, workspace)
    Swag.require(workspace.scene() == scene and scene.views.count == 4 and scene.active == 3)
    Swag.require(scene.views[3].path == replacement and scene.views[0].document == original)

    // Several files still open together in a new scene.
    Swag.require(host.dropFiles(right, [first.toString(), second.toString()]) == .Copy)
    openViews(&host, workspace)
    Swag.require(workspace.scenes.count == 2 and workspace.documentCount() == 2)
    Swag.require(scene.views[1].path == replacement)

    Swag.require(host.dropFilesOnWnd(workspace.tabs, [path]) == .Copy)
    openViews(&host, workspace)
    Swag.require(workspace.scenes.count == 3 and workspace.activeDocument().currentFile == replacement)
    Swag.require(not workspace.closeFileButton.isLocallyVisible())
    let tabs = workspace.tabs
    let item = tabs.items[workspace.active]
    var close = tabs.localToSurface(Math.Point{item.right() + SceneTabs.CloseSize * 0.5, item.vertCenter()})
    host.surface.surfaceToScreen(&close)
    Swag.require(tabs.showsClose(workspace.active))
    var above = tabs.localToSurface(Math.Point{item.right() + SceneTabs.CloseSize * 0.5, item.y + 1})
    host.surface.surfaceToScreen(&above)
    host.click(above)
    Swag.require(workspace.scenes.count == 3)
    host.click(close)
    Swag.require(workspace.scenes.count == 2)
}

// A distant hole keeps its physical position. Cancelling an open leaves it empty, and closing
// that focus never closes a neighbour. Both file and folder shortcuts operate in the chosen cell.
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, light: true, width: 780, height: 500)
    defer host.shutdown()
    let first = expect Path.absolute(scopeTestDataPath("viewer.png"))
    let other = expect Path.absolute(scopeTestDataPath("sample.cpp"))
    workspace.openScene([first, other], .Grid3)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    let original = workspace.activeDocument()
    var corner = workspace.localToSurface(workspace.gridCellRect(scene, 8).center())
    host.surface.surfaceToScreen(&corner)
    host.click(corner)
    Swag.require(workspace.vacancy and workspace.activeDocument() == workspace.vacancy)
    Swag.require(workspace.vacantCell == 8 and scene.views.count == 2)
    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    host.shortcut(.O, .Control)
    Swag.require(host.autoHandled and workspace.vacancy and scene.views.count == 2)
    host.keyPress(.W, .Control)
    Swag.require(not workspace.vacancy and workspace.activeDocument() == original and scene.views.count == 2)
    host.keyPress(.Down, .Alt)
    Swag.require(workspace.vacancy and workspace.vacantCell == 3)
    host.keyPress(.Up, .CtrlAlt)
    Swag.require(workspace.vacantCell == 0 and scene.viewInCell(3) == 0)
    host.keyPress(.Down, .CtrlAlt)
    Swag.require(workspace.vacantCell == 3 and scene.viewInCell(0) == 0)
    host.acceptModalFileDialog(other)
    host.shortcut(.O, .Control)
    openViews(&host, workspace)
    Swag.require(not workspace.vacancy and workspace.scenes.count == 1 and scene.views.count == 3)
    Swag.require(scene.cellOf(scene.active) == 3 and workspace.activeDocument().currentFile == other)
    host.click(corner)
    let folder = Path.directoryName(first) orelse ""
    host.acceptModalFileDialog(folder)
    host.shortcut(.E, .Control)
    host.pump()
    Swag.require(host.autoHandled and workspace.activeDocument().isExploring() and scene.cellOf(scene.active) == 8)
    let saved = saveViewerState(workspace.primary)
    host.keyPress(.W, .Control)
    Swag.require(scene.cellOf(scene.active) == 3)
    host.keyPress(.W, .Control)
    host.keyPress(.W, .Control)
    Swag.require(scene.views.count == 1 and scene.layout == .Single and workspace.activeDocument() == original)
    host.keyPress(.W, .Control)
    Swag.require(not workspace.scene() and workspace.primary.home.isLocallyVisible())
    loadViewerState(workspace.primary, saved.toSlice())
    workspace.restoreScenes()
    openViews(&host, workspace)
    let restored = unwrap workspace.scene()
    Swag.require(restored.views.count == 4 and restored.cellOf(restored.active) == 8)
    Swag.require(restored.viewInCell(2) == Swag.U64.Max and restored.viewInCell(3) == 2)
}

// The grid owns file drops over a video, including files the standalone player can attach.
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()

    let first = expect Path.absolute(scopeTestDataPath("sample.cpp"))
    let video = scopeTestDataPath("viewer.avi")
    let subtitles = expect Path.absolute(scopeTestDataPath("viewer.srt"))
    workspace.openScene([first, video], .SideBySide)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    let film  = assume cast(*Viewers.Film.Panel, scene.views[1].document!.currentView)
    waitForVideoFrame(film)
    Swag.require(host.dropFilesOnWnd(film.imageView, [subtitles.toString()]) == .Copy)
    openViews(&host, workspace)
    Swag.require(scene.views[0].path == first and scene.views[1].path == subtitles)
}

// In a curtain comparison the visible side under the pointer owns the drop.
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    let left = expect Path.absolute(scopeTestDataPath("viewer.png"))
    let right = expect Path.absolute(scopeTestDataPath("viewer.progressive.jpg"))
    let replacement = expect Path.absolute(scopeTestDataPath("title.png"))
    workspace.openScene([left, right], .SideBySide, compare: true)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    let comparison = unwrap workspace.comparison
    comparison.setPictureMode(.Curtain)
    comparison.separator = 0.72

    var point = workspace.localToSurface(Math.Point{workspace.clientRect().width * 0.6, workspace.stripInset() + 120})
    host.surface.surfaceToScreen(&point)
    Swag.require(host.dragFilesOver(point, [replacement.toString()]) == .Copy and workspace.dropView == 0)
    Swag.require(host.dropFiles(point, [replacement.toString()]) == .Copy)
    openViews(&host, workspace)
    Swag.require(workspace.comparisonVisible() and comparison.mode == .Curtain)
    Swag.require(scene.views[0].path == replacement and scene.views[1].path == right)
}

// The close control belongs to its visible cell. The caption takes over for the last file.
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    let files = [scopeTestDataPath("comprehensive.txt"), scopeTestDataPath("sample.cpp"), scopeTestDataPath("viewer.srt")]
    workspace.openScene(files, .Grid2)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    let original = workspace.activeDocument()
    let last = unwrap scene.views[2].document
    let closeFile = workspace.closeFileButton
    Swag.require(not closeFile.isLocallyVisible())
    let middle = unwrap scene.views[1].document
    Swag.require(not middle.cellCaption.isLocallyVisible())
    var pointer = workspace.localToSurface(workspace.viewRect(scene, 1).center())
    host.surface.surfaceToScreen(&pointer)
    host.moveMouse(pointer)
    Swag.require(middle.cellCaption.isLocallyVisible())
    let closePoint = middle.cellCaptionClose.surfaceRect().center()
    let target = host.surfaceWnd.windowAt(closePoint.x, closePoint.y)
    Swag.require(target == middle.cellCaptionClose, Format.toString("hit '%' at % in %", target?.id orelse "", closePoint, middle.cellCaption.position))
    host.clickWnd(middle.cellCaptionClose)
    Swag.require(scene.views.count == 2 and scene.views[1].document == last)
    Swag.require(workspace.activeDocument() == original)
    pointer = workspace.localToSurface(workspace.viewRect(scene, 1).center())
    host.surface.surfaceToScreen(&pointer)
    host.moveMouse(pointer)
    host.clickWnd(last.cellCaptionClose)
    Swag.require(scene.views.count == 1 and workspace.activeDocument() == original)
    Swag.require(scene.layout == .Single and not scene.linked and not scene.compared)
    Swag.require(original.position == workspace.clientRect())
    Swag.require(closeFile.isLocallyVisible() and not original.cellCaption.isLocallyVisible())
    host.clickWnd(closeFile)
    Swag.require(workspace.scenes.isEmpty() and workspace.primary.home.isLocallyVisible())
    Swag.require(not closeFile.isLocallyVisible())
}

// Shared caption actions follow the selected file, and screen and media settings belong to the window.
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    workspace.openScene([scopeTestDataPath("viewer.png"), scopeTestDataPath("document-outline.pdf")], .SideBySide)
    openViews(&host, workspace)
    let scene   = unwrap workspace.scene()
    let picture = unwrap scene.views[0].document
    let pdf     = unwrap scene.views[1].document
    let outline = picture.outlineCaptionButton
    let info    = picture.informationCaptionButton
    Swag.require(not outline.isLocallyVisible())

    workspace.selectView(1)
    Swag.require(outline.isLocallyVisible() and Utf8.contains(outline.toolTip, "document-outline.pdf"))
    Swag.require(Utf8.contains(pdf.viewerCaptionButton.toolTip, "document-outline.pdf"))
    let foot = pdf.readingLine.surfaceRect()
    let left = pdf.documentArea().x
    host.clickWnd(outline)
    Swag.require(pdf.currentSidePanelButton!.isChecked)
    Swag.require(pdf.documentArea().x > left and pdf.readingLine.surfaceRect() == foot)

    let area = pdf.documentArea()
    host.clickWnd(info)
    Swag.require(info.isChecked and pdf.infoSheet.isLocallyVisible() and not picture.infoSheet.isLocallyVisible())
    Swag.require(pdf.documentArea() == area)

    workspace.selectView(0)
    Swag.require(not outline.isLocallyVisible() and not info.isChecked)
    Swag.require(Utf8.contains(info.toolTip, "viewer.png"))
    host.clickWnd(info)
    Swag.require(picture.infoSheet.isLocallyVisible() and not pdf.infoSheet.isLocallyVisible())

    workspace.selectView(1)
    pdf.applyOnlineMedia(false, false)
    Swag.require(not picture.onlineMovies and not picture.onlineMusic and not pdf.onlineMovies and not pdf.onlineMusic)
    host.keyPress(.F11)
    Swag.require(picture.fullScreen and pdf.fullScreen)
    workspace.selectView(0)
    host.keyPress(.F11)
    Swag.require(not picture.fullScreen and not pdf.fullScreen and picture.fullScreenCaptionButton.isLocallyVisible())
}

#test
{
    let first  = scopeTestDataPath("comprehensive.txt")
    let second = scopeTestDataPath("sample.cpp")
    let third  = scopeTestDataPath("viewer.srt")
    var saved: String
    scope
    {
        var host: Testing.HeadlessHost
        let workspace = testWorkspace(&host)
        defer host.shutdown()
        workspace.openScene([first, second], .Stacked)
        openViews(&host, workspace)
        workspace.selectView(0)
        let window = workspace.activeDocument()
        for choice, index in window.choices where choice.key == "hex" do
            window.selectViewer(cast(u32, index))
        completeQueuedViewerFile(&host, window)
        Swag.require(window.choices[window.activeChoiceIndex].key == "hex")
        let hex = assume cast(*Viewers.Hex.Panel, window.currentView)
        Swag.require(hex.revealOffset(32, 1) and hex.revealOffset(96, 1))
        Swag.require(hex.navigateHistory(-1) and hex.grid.caret == 32)
        window.searchMatchCaseOption = true
        window.searchBox.setText("53", notify: false)
        workspace.toggleMaximized()
        workspace.openDocument(third)
        openViews(&host, workspace)
        workspace.selectScene(0)
        openViews(&host, workspace)
        let resumed = workspace.activeDocument()
        host.fireTimer(resumed.fileWatchTimer)
        let reopened = assume cast(*Viewers.Hex.Panel, resumed.currentView)
        Swag.require(reopened.grid.caret == 32)
        Swag.require(reopened.navigateHistory(1) and reopened.grid.caret == 96)
        workspace.selectScene(1)
        openViews(&host, workspace)
        saved = saveViewerState(workspace.primary)
    }

    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    loadViewerState(workspace.primary, saved.toSlice())
    workspace.startupFiles.add(first)
    workspace.startupFiles.add(third)
    workspace.startupLayout = .SideBySide
    workspace.sendStateEvent(.Init)
    openViews(&host, workspace)
    Swag.require(workspace.scenes.count == 3 and workspace.active == 2)
    Swag.require(workspace.scene()!.layout == .SideBySide and workspace.documentCount() == 2)
    workspace.selectScene(0)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    Swag.require(scene.layout == .Stacked and scene.maximized and scene.active == 0)
    Swag.require(not scene.views[1].document!.isLocallyVisible())
    let restored = workspace.activeDocument()
    Swag.require(restored.choices[restored.activeChoiceIndex].key == "hex")
    Swag.require(restored.searchMatchCaseOption and restored.searchBox.text() == "53")
}

#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    let first = scopeTestDataPath("sample.cpp")
    let files = [first, scopeTestDataPath("comprehensive.txt")]
    workspace.openScene(files, .Stacked)
    openViews(&host, workspace)

    let scene = unwrap workspace.scene()
    host.keyPress(.D3, .Control | .Alt)
    Swag.require(scene.layout == .Grid3 and scene.dimensions() == {3, 3})
    host.keyPress(.D4, .Control | .Alt)
    Swag.require(scene.layout == .Grid4 and scene.dimensions() == {4, 4})
    host.keyPress(.D2, .Control | .Alt)
    Swag.require(scene.layout == .Grid2 and scene.dimensions() == {2, 2})
    host.keyPress(.D0, .Control | .Alt)
    Swag.require(scene.layout == .Auto and scene.dimensions() == {2, 1})
    host.keyPress(.Oem5, .Control)
    Swag.require(scene.layout == .SideBySide)

    host.paint(&host.surfaceWnd)
    var divider = workspace.localToSurface(workspace.dividerRect().center())
    host.surface.surfaceToScreen(&divider)
    host.drag(divider, divider + Math.Point{120, 0})
    Swag.require(scene.split > 0.55)
    divider = workspace.localToSurface(workspace.dividerRect().center())
    host.surface.surfaceToScreen(&divider)
    host.doubleClick(divider)
    Swag.require(scene.split == 0.5)

    host.keyPress(.F)
    Swag.require(scene.maximized and not scene.views[1].document!.isLocallyVisible())
    Swag.require(workspace.maxHint!.surfaceRect().bottom() <= workspace.activeDocument().readingLine.surfaceRect().y)
    host.keyPress(.Right, .Alt)
    Swag.require(scene.active == 1 and scene.views[1].document!.isLocallyVisible())
    host.keyPress(.Escape)
    Swag.require(not scene.maximized and scene.views[0].document!.isLocallyVisible())

    let right = unwrap scene.views[1].document
    let third = scopeTestDataPath("viewer.srt")
    workspace.openDocument(third)
    openViews(&host, workspace)
    host.paint(&host.surfaceWnd)
    let tabs     = workspace.tabs
    var otherTab = tabs.localToSurface(tabs.items[0].center())
    host.surface.surfaceToScreen(&otherTab)
    host.click(otherTab)
    openViews(&host, workspace)
    Swag.require(workspace.scene() == scene and workspace.activeDocument() != right)
    var lastTab = tabs.localToSurface(tabs.items[1].center())
    host.surface.surfaceToScreen(&lastTab)
    host.click(lastTab, .Middle)
    Swag.require(workspace.scenes.count == 1 and not tabs.isLocallyVisible())
}

// Scene shortcuts follow the user's bindings. The lens retains the input while it is open.
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    workspace.openDocument(scopeTestDataPath("viewer.srt"))
    openViews(&host, workspace)
    workspace.openScene([scopeTestDataPath("viewer.png"), scopeTestDataPath("sample.cpp")], .SideBySide)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    let document = workspace.activeDocument()
    document.lens.open("grid")
    host.keyPress(.Tab, .Control)
    host.keyPress(.W, .Control)
    Swag.require(document.lens.isOpen() and workspace.scene() == scene and workspace.documentCount() == 2 and not workspace.switcher)
    host.keyPress(.Escape)
    Swag.require(document.lens.isOpen())
    host.keyPress(.Escape)
    Swag.require(not document.lens.isOpen())
    document.registerKeyShortcut(.None, .F, ViewerCommands.Information)
    document.registerKeyShortcut(.Control, .W, ViewerCommands.Information)
    document.registerKeyShortcut(.CtrlShift, .F8, SceneCommands.Maximize)
    document.registerKeyShortcut(.CtrlShift, .F9, ViewerCommands.Close)
    host.keyPress(.F)
    host.keyPress(.W, .Control)
    Swag.require(not scene.maximized and scene.views.count == 2)
    host.keyPress(.F8, .CtrlShift)
    Swag.require(scene.maximized)
    host.keyPress(.F9, .CtrlShift)
    Swag.require(workspace.scene() == scene and scene.views.count == 1 and not scene.maximized)
}
