#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Audio

#test
{
    let files = viewerStartupFiles(["swagscope", "swag.test", "--grid", "one.swg", "two.txt"])
    Swag.require(files.count == 2)
    Swag.require(files[0] == "one.swg" and files[1] == "two.txt")

    var comparison: TextComparison
    comparison.compare("start\r\nold\r\nkeep\r\nend", "start\r\nnew\r\nextra\r\nkeep\r\nend", {})
    Swag.require(comparison.rows.count == 5)
    Swag.require(comparison.changes.count == 1 and comparison.changes[0] == 1)
    Swag.require(comparison.rows[2].left == Swag.U32.Max and comparison.rows[2].right == 2)
    Swag.require(comparison.rows[3].left == 2 and comparison.rows[3].right == 3)

    comparison.compare(" Alpha \r\n", "alpha\n", {ignoreWhitespace: true, ignoreCase: true, ignoreEndings: true})
    Swag.require(comparison.changes.isEmpty())
    comparison.compare("alpha\r\n", "alpha\n", {})
    Swag.require(comparison.changes.count == 1)
}

#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()

    let firstPath  = scopeTestDataPath("comprehensive.txt")
    let secondPath = scopeTestDataPath("sample.cpp")
    workspace.openDocument(firstPath)
    openViews(&host, workspace)
    let first = workspace.activeDocument()
    let text  = assume cast(*Viewers.PlainText.Panel, first.currentView)
    text.setZoom(145, remember: false)
    Swag.require(not workspace.tabs.isLocallyVisible())

    workspace.insertDocument(secondPath, .Right)
    openViews(&host, workspace)
    let second = workspace.activeDocument()
    Swag.require(second != first)
    Swag.require(workspace.scene()!.views.count == 2)
    Swag.require(first.currentView == text and text.zoomPercent == 145)

    workspace.selectView(0)
    workspace.toggleMaximized()
    Swag.require(first.isLocallyVisible() and not second.isLocallyVisible())
    workspace.toggleMaximized()
    Swag.require(second.isLocallyVisible())
    Swag.require(workspace.moveView(.Right, swap: true))
    Swag.require(workspace.activeDocument() == first and workspace.scene()!.active == 1)

    workspace.openDocument(scopeTestDataPath("viewer.srt"))
    openViews(&host, workspace)
    Swag.require(workspace.scenes.count == 2 and workspace.tabs.isLocallyVisible())
    Swag.require(workspace.scenes[0]!.views[1].document == null)
    workspace.selectScene(0)
    openViews(&host, workspace)
    host.fireTimer(workspace.activeDocument().fileWatchTimer)
    let resumed = assume cast(*Viewers.PlainText.Panel, workspace.activeDocument().currentView)
    Swag.require(resumed.zoomPercent == 145)

    workspace.closeView()
    Swag.require(workspace.scene()!.views.count == 1)
    Swag.require(workspace.activeDocument().currentFile == secondPath)
    workspace.closeView()
    Swag.require(workspace.scenes.count == 1 and not workspace.tabs.isLocallyVisible())
}

#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()

    let paths = [scopeTestDataPath("comprehensive.txt"), scopeTestDataPath("sample.cpp")]
    workspace.openScene(paths, .SideBySide, compare: true)
    openViews(&host, workspace)
    Swag.require(workspace.comparisonVisible())
    let compare = unwrap workspace.comparison
    compare.operation.task.wait()
    host.pump()
    Swag.require(not compare.text.changes.isEmpty())
    compare.jump(0)
    Swag.require(workspace.activeDocument().runCommand(ComparisonCommands.Next))
    Swag.require(compare.selectedChange == 1 % compare.text.changes.count)
    workspace.activeDocument().toggleInformation()
    Swag.require(workspace.comparisonSheet!.panel.isLocallyVisible())
    Swag.require(workspace.comparisonSheet.facts.count > 2)
    let sheet = workspace.comparisonSheet
    let top   = workspace.stripInset() + workspace.themeMetrics().floating_Inset
    Swag.require(sheet.panel.position.y == top)
    Swag.require(sheet.panel.position.bottom() < workspace.clientRect().bottom() - workspace.themeMetrics().floating_Inset)
    workspace.setLayout(.Grid3)
    Swag.require(not workspace.comparisonVisible() and workspace.documentCount() == 2)
    Swag.require(not sheet.panel.isLocallyVisible() and workspace.scene()!.layout == .Grid3)
}

#test
{
    var reference: Array'f32
    reference.resize(3000)
    for index in reference.count
    {
        let phase = cast(f64, index)
        reference[index] = cast(f32, Math.sin(phase * 0.0321) + Math.cos(phase * 0.0779) * Math.sin(phase * 0.012))
    }

    var recording: Array'f32
    recording.resize(173)
    recording.add(reference.toSlice())
    let result = estimateSoundOffset(reference.toSlice(), recording.toSlice(), 400)
    Swag.require(result.reliable and result.samples == 173)
}

#test
{
    let left  = scopeTestDataPath("comprehensive.txt")
    let right = scopeTestDataPath("sample.cpp")
    var saved: String
    scope
    {
        var host: Testing.HeadlessHost
        let workspace = testWorkspace(&host)
        defer host.shutdown()
        let files = [left, right]
        workspace.openScene(files, .Stacked)
        openViews(&host, workspace)
        workspace.setSceneLink(MediaCommands.Linked, true)
        workspace.setSceneLink(MediaCommands.Scroll, true)
        workspace.openDocument(scopeTestDataPath("viewer.srt"))
        openViews(&host, workspace)
        saved = saveViewerState(workspace.primary)
    }

    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    loadViewerState(workspace.primary, saved.toSlice())
    workspace.restoreScenes()
    openViews(&host, workspace)
    Swag.require(workspace.scenes.count == 2 and workspace.active == 1)
    Swag.require(workspace.scenes[0]!.layout == .Stacked)
    Swag.require(workspace.scenes[0]!.linked and workspace.scenes[0]!.links.scroll)
    host.shortcut(.Tab, .Control)
    Swag.require(workspace.switcher != null)
    host.keyPress(.W, .Control)
    Swag.require(workspace.switcher != null and workspace.scenes.count == 2)
    var release = KeyEvent{kind: .Released, key: .Control}
    workspace.activeDocument().sendEvent(&release)
    openViews(&host, workspace)
    Swag.require(workspace.active == 0 and workspace.documentCount() == 2)
}

#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()

    let first  = scopeTestDataPath("comprehensive.txt")
    let second = scopeTestDataPath("sample.cpp")
    workspace.openDocument(first)
    openViews(&host, workspace)
    let original = workspace.activeDocument()
    let path     = second.toString()
    let target   = workspace.overlay.dropRect(.Below).center()
    let local    = workspace.localToSurface(target)
    let area     = host.surface.position
    let point    = Math.Point{area.x + local.x * workspace.deviceScale(), area.y + local.y * workspace.deviceScale()}
    let left     = workspace.overlay.dropRect(.Left)
    let middle   = workspace.overlay.dropRect(.Replace)
    let gap      = workspace.overlay.localToSurface(Math.Point{(left.right() + middle.x) * 0.5, middle.vertCenter()})
    let away     = Math.Point{area.x + gap.x * workspace.deviceScale(), area.y + gap.y * workspace.deviceScale()}
    Swag.require(host.dragFilesOver(away, [path]) == .None)
    Swag.require(workspace.dragging and workspace.dropTarget == .None)
    Swag.require(host.dropFiles(away, [path]) == .None)
    Swag.require(not workspace.dragging and original.currentFile == first)
    Swag.require(host.dragFilesOver(point, [path]) == .Copy)
    Swag.require(workspace.dragging and workspace.dropTarget == .Below)
    Swag.require(host.dropFiles(point, [path]) == .Copy)
    openViews(&host, workspace)
    Swag.require(workspace.scene()!.layout == .Stacked)
    Swag.require(original.currentFile == first and workspace.activeDocument().currentFile == second)
    host.keyPress(.Up, .Alt)
    Swag.require(workspace.activeDocument() == original)
    host.keyPress(.W, .Control)
    Swag.require(workspace.documentCount() == 1 and workspace.activeDocument().currentFile == second)
}

#test
{
    let path = scopeTestDataPath("sample.cpp")
    var expected: Image
    scope
    {
        var host: Testing.HeadlessHost
        let original = createFramedViewerWindow(&host, true, 1080, 640)
        defer host.shutdown()
        original.openFile(path)
        completeQueuedViewerFile(&host, original)
        host.surface.clearFocus()
        expected = host.renderSettled(&host.surfaceWnd)
    }

    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, light: true)
    defer host.shutdown()
    workspace.openDocument(path)
    openViews(&host, workspace)
    host.surface.clearFocus()
    let actual = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImagesNear(&expected, &actual, "scene.single")
}

#test
{
    var left, right: Viewers.Binary.Report
    left.beginGroup("Header")
    left.field(0, 4, "Revision", "1")
    left.field(4, 4, "Attributes", "Ready")
    left.endGroup()
    right.beginGroup("Header")
    right.field(0, 4, "Revision", "2")
    right.field(4, 4, "Extra", "Present")
    right.field(8, 4, "Attributes", "Ready")
    right.endGroup()

    var compare: TextComparison
    compare.compareReports(&left, &right)
    Swag.require(compare.rows.count == 4)
    Swag.require(compare.rows[1].changed and compare.rows[1].left == 1 and compare.rows[1].right == 1)
    Swag.require(compare.rows[2].changed and compare.rows[2].left == Swag.U32.Max)
    Swag.require(not compare.rows[3].changed and compare.rows[3].left == 2 and compare.rows[3].right == 3)
    Swag.require(compare.changes.count == 1)
}

#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    let base   = Env.getSpecialDirectory(.Temp)
    let first  = expect videoPreviewFileAt(Path.combine(base, "scope-multiview-rate-4.avi"), 8, 4)
    let second = expect videoPreviewFileAt(Path.combine(base, "scope-multiview-rate-10.avi"), 20, 10)
    defer catch File.delete(first)
    defer catch File.delete(second)

    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    workspace.openScene([first, second], .Grid2)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    let a     = unwrap ScenePlayer.from(scene.views[0].document).film
    let b     = unwrap ScenePlayer.from(scene.views[1].document).film
    Swag.require(scene.linked and not a.playing and not b.playing)
    Swag.require(not a.sceneSilent and b.sceneSilent)
    host.keyPress(.Right, .Control)
    for 400
    {
        host.tickTimer(workspace.transport!.timer)
        if a.frameIndex == 1 and b.frameIndex == 2 do
            break
        Threading.Thread.sleep(1'ms)
    }

    Swag.require(a.frameIndex == 1 and b.frameIndex == 2)
    workspace.selectView(1)
    workspace.synchronizeMedia()
    Swag.require(a.sceneSilent and not b.sceneSilent)
}

#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()

    let folder = Path.directoryName(scopeTestDataPath("sample.cpp")) orelse ""
    workspace.primary.openExplorer(folder)
    let explorer = unwrap workspace.primary.explorer
    completeExplorer(&host, explorer)
    explorer.setMode(.Small)
    var first, second = Swag.U64.Max
    for entry, row in explorer.shown
    {
        let name: string = explorer.entries[entry].name
        switch name
        {
        case "comprehensive.txt": first = row
        case "sample.cpp":        second = row
        }
    }

    Swag.require(first < explorer.shown.count and second < explorer.shown.count)
    explorer.grid.select(first)
    explorer.grid.select(second, .Control)
    Swag.require(explorer.selectionPaths().count == 2)
    explorer.grid.select(second, .Control)
    Swag.require(explorer.selectionPaths().count == 1)
    explorer.grid.select(second, .Control)
    Swag.require(workspace.primary.runCommand(SceneCommands.CompareSelection))
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    Swag.require(scene.views.count == 2 and scene.compared and scene.linked)
}

#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    let files = [scopeTestDataPath("sample.svg"), scopeTestDataPath("viewer.png")]
    workspace.openScene(files, .SideBySide, compare: true)
    openViews(&host, workspace)
    let comparison = unwrap workspace.comparison
    comparison.setPictureMode(.Curtain)
    host.paint(&host.surfaceWnd)
    Swag.require(comparison.vectors[0].image.isValid())
    Swag.require(comparison.vectors[0].texture.isValid())
    comparison.separator = 0.25
    workspace.openDocument(scopeTestDataPath("viewer.md"))
    openViews(&host, workspace)
    workspace.selectScene(0)
    openViews(&host, workspace)
    Swag.require(comparison.mode == .Curtain and comparison.separator == 0.25)
}

#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    let files = [scopeTestDataPath("viewer.wav"), scopeTestDataPath("pacman_beginning.wav")]
    workspace.openScene(files, .Stacked)
    openViews(&host, workspace)
    let scene  = unwrap workspace.scene()
    let first  = unwrap ScenePlayer.from(scene.views[0].document).sound
    let second = unwrap ScenePlayer.from(scene.views[1].document).sound
    workspace.synchronizeMedia()
    Swag.require(first.waveform.sceneSpan == second.waveform.sceneSpan and first.waveform.sceneSpan >= first.duration)
    Swag.require(first.waveform.sceneStart == second.waveform.sceneStart)
    workspace.playScene()
    Swag.require(first.playing and first.voice != null and not first.sceneSilent)
    Swag.require(second.playing and second.sceneSilent and second.voice == null)
}
