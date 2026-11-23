#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()

    let first  = scopeTestDataPath("comprehensive.txt")
    let second = scopeTestDataPath("sample.cpp")
    let third  = scopeTestDataPath("viewer.srt")
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

#test
{
    let first  = scopeTestDataPath("comprehensive.txt")
    let second = scopeTestDataPath("sample.cpp")
    let path   = second.toString()
    for target in [SceneDropTarget.Left, .Right, .Below, .Replace, .NewTab]
    {
        var host: Testing.HeadlessHost
        let workspace = testWorkspace(&host)
        defer host.shutdown()
        workspace.openDocument(first)
        openViews(&host, workspace)
        let original = workspace.activeDocument()

        var point = workspace.overlay.localToSurface(workspace.overlay.dropRect(target).center())
        host.surface.surfaceToScreen(&point)
        Swag.require(host.dragFilesOver(point, [path]) == .Copy and workspace.dropTarget == target)
        Swag.require(host.dropFiles(point, [path]) == .Copy)
        openViews(&host, workspace)
        let scene = unwrap workspace.scene()
        Swag.require(workspace.activeDocument().currentFile == second and not workspace.dragging)
        switch target
        {
        case .NewTab:
            Swag.require(workspace.scenes.count == 2 and scene.views.count == 1)
            Swag.require(workspace.scenes[0]!.views[0].path == first)

        case .Replace:
            Swag.require(workspace.scenes.count == 1 and
                         scene.views.count == 1 and
                         workspace.activeDocument() == original)

        default:
            Swag.require(workspace.scenes.count == 1 and scene.views.count == 2)
            Swag.require(scene.layout == (target == .Below ? .Stacked : .SideBySide))
            Swag.require(scene.views[target == .Left ? 1 : 0].document == original and original.currentFile == first)
        }
    }
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
    var divider = workspace.overlay.localToSurface(workspace.overlay.divider().center())
    host.surface.surfaceToScreen(&divider)
    host.drag(divider, divider + Math.Point{120, 0})
    Swag.require(scene.split > 0.55)
    divider = workspace.overlay.localToSurface(workspace.overlay.divider().center())
    host.surface.surfaceToScreen(&divider)
    host.doubleClick(divider)
    Swag.require(scene.split == 0.5)

    host.keyPress(.F)
    Swag.require(scene.maximized and not scene.views[1].document!.isLocallyVisible())
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
