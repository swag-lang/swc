#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    let paths = [scopeTestDataPath("comprehensive.txt"), scopeTestDataPath("sample.cpp")]
    workspace.openScene(paths, .SideBySide)
    openViews(&host, workspace)
    let pair = unwrap workspace.scene()
    pair.split = 0.62

    host.clickWnd(workspace.newTabButton)
    Swag.require(workspace.scenes.count == 2 and workspace.scene()!.views.isEmpty())
    Swag.require(workspace.tabs.isVisible() and workspace.activeDocument().home.isVisible())
    host.acceptModalFileDialog(scopeTestDataPath("viewer.md"))
    host.shortcut(.O, .Control)
    openViews(&host, workspace)
    Swag.require(host.autoHandled and workspace.scenes.count == 2 and workspace.documentCount() == 1)
    Swag.require(Path.fileName(workspace.activeDocument().currentFile) == "viewer.md")

    workspace.selectScene(0)
    openViews(&host, workspace)
    Swag.require(workspace.scene() == pair and pair.layout == .SideBySide and pair.split == 0.62)
    let document = workspace.activeDocument()
    let closed = document.runCommand(TabCommands.CloseOthers)
    Swag.require(closed and workspace.scenes.count == 1 and workspace.activeDocument() == document)
    let cleared = document.runCommand(TabCommands.CloseAll)
    Swag.require(cleared and workspace.scenes.isEmpty() and workspace.primary.home.isVisible())
}

#test
{
    let root = Testing.tempFilePath("scope-tabs-", "")
    let folder = Path.combine(root, "folder")
    expect Directory.create(folder, recurse: true)
    defer catch Directory.delete(root, recurse: true)
    discard expect File.writeAllText(Path.combine(folder, "needle.txt"), "text")

    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    workspace.primary.openExplorer(root)
    let explorer = unwrap workspace.primary.explorer
    completeExplorer(&host, explorer)
    explorer.navigate(folder)
    completeExplorer(&host, explorer)
    explorer.setMode(.Details)
    explorer.filter.setText("needle")

    host.keyPress(.T, .Control)
    Swag.require(workspace.scenes.count == 2 and workspace.scene()!.views.isEmpty())
    host.acceptModalFileDialog(folder)
    host.shortcut(.E, .Control)
    openViews(&host, workspace)
    let second = unwrap workspace.activeDocument().explorer
    completeExplorer(&host, second)
    Swag.require(workspace.active == 1 and workspace.scenes.count == 2)
    second.setMode(.Names)
    second.filter.setText("another filter")

    workspace.selectScene(0)
    let first = unwrap workspace.activeDocument().explorer
    completeExplorer(&host, first)
    Swag.require(Path.equals(first.listing.path, folder) and first.history.canGoBack())
    Swag.require(first.mode == .Details and first.filter.text() == "needle")
    workspace.selectScene(1)
    let resumed = unwrap workspace.activeDocument().explorer
    completeExplorer(&host, resumed)
    Swag.require(resumed.mode == .Names and resumed.filter.text() == "another filter")
}

#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, light: true)
    defer host.shutdown()
    let created = workspace.activeDocument().runCommand(TabCommands.NewGrid)
    Swag.require(created and workspace.tabs.isVisible())
    let scene = unwrap workspace.scene()
    Swag.require(scene.views.isEmpty() and scene.cellCount() == 4)

    let saved = saveViewerState(workspace.primary)
    workspace.closeTabs()
    loadViewerState(workspace.primary, saved.toSlice())
    workspace.restoreScenes()
    let restored = unwrap workspace.scene()
    Swag.require(restored.views.isEmpty() and restored.layout == .Grid2 and restored.cellCount() == 4)

    var point = workspace.localToSurface(workspace.gridCellRect(restored, 2).center())
    host.surface.surfaceToScreen(&point)
    let paths = [scopeTestDataPath("comprehensive.txt"), scopeTestDataPath("sample.cpp")]
    let effect = host.dropFiles(point, [paths[0].toString(), paths[1].toString()])
    Swag.require(effect == .Copy and workspace.scenes.count == 1 and workspace.documentCount() == 2)
    Swag.require(restored.cellOf(0) == 2 and restored.cellOf(1) == 3 and restored.layout == .Grid2)
    openViews(&host, workspace)
    workspace.closeView()
    workspace.closeView()
    Swag.require(workspace.scene() == restored and restored.views.isEmpty() and restored.cellCount() == 4)

    let closed = workspace.activeDocument().runCommand(TabCommands.Close)
    Swag.require(closed and workspace.scenes.isEmpty() and workspace.primary.home.isVisible())
}

#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    workspace.openDocument(scopeTestDataPath("sample.cpp"))
    openViews(&host, workspace)
    let first = unwrap workspace.scene()

    host.acceptModalFileDialog(scopeTestDataPath("viewer.md"))
    let opened = workspace.activeDocument().runCommand(TabCommands.OpenFile)
    openViews(&host, workspace)
    Swag.require(opened and host.autoHandled and workspace.scenes.count == 2 and workspace.active == 1)
    Swag.require(workspace.scene()!.manual and Path.fileName(workspace.activeDocument().currentFile) == "viewer.md")

    let tabs = workspace.tabs
    var point = tabs.localToSurface(tabs.items[0].center())
    host.surface.surfaceToScreen(&point)
    host.clickPopupMenuItemWhenShown(TabCommands.CloseOthers)
    host.click(point, .Right)
    Swag.require(host.autoHandled and workspace.scenes.count == 1 and workspace.scene() == first)
    openViews(&host, workspace)
    Swag.require(Path.fileName(workspace.activeDocument().currentFile) == "sample.cpp")
}
