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

    workspace.openBeside(secondPath)
    openViews(&host, workspace)
    let second = workspace.activeDocument()
    Swag.require(second != first)
    Swag.require(workspace.scene()!.views.count == 2)
    Swag.require(first.currentView == text and text.zoomPercent == 145)

    workspace.selectView(0)
    Swag.require(first.runCommand(SceneCommands.Layouts[0]))
    Swag.require(first.isLocallyVisible() and not second.isLocallyVisible())
    Swag.require(workspace.scene()!.layout == .SideBySide and workspace.scene()!.visibleLayout() == .Single)
    host.keyPress(.Escape)
    Swag.require(second.isLocallyVisible() and workspace.scene()!.visibleLayout() == .SideBySide)
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
    Swag.require(workspace.activeDocument().currentFile == (expect Path.absolute(secondPath)))
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

    let first  = expect Path.absolute(scopeTestDataPath("comprehensive.txt"))
    let second = expect Path.absolute(scopeTestDataPath("sample.cpp"))
    workspace.openScene([first, second], .Stacked)
    openViews(&host, workspace)
    let original = workspace.activeDocument()
    host.keyPress(.Down, .Alt)
    Swag.require(workspace.activeDocument().currentFile == second)
    host.keyPress(.Up, .Alt)
    Swag.require(workspace.activeDocument() == original)
    host.keyPress(.W, .Control)
    Swag.require(workspace.documentCount() == 1 and workspace.activeDocument().currentFile == second)
}

// A single scene keeps the standalone reader's document layout below its workspace caption.
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
    var actual = host.renderSettled(&host.surfaceWnd)
    let strip  = cast(s32, workspace.stripInset())
    expected.crop(0, strip, expected.width, expected.height - strip)
    actual.crop(0, strip, actual.width, actual.height - strip)
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
        host.tickTimer(workspace.mediaTimer)
        if a.frameIndex == 1 and b.frameIndex == 2 do
            break
        Threading.Thread.sleep(1'ms)
    }

    Swag.require(a.frameIndex == 1 and b.frameIndex == 2)
    workspace.selectView(1)
    workspace.synchronizeMedia()
    Swag.require(a.sceneSilent and not b.sceneSilent)
}

// The shortest film can stop or advance without interrupting the other cell.
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    let folder = Testing.tempFilePath("scope-scene-playback-", "")
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)
    let first = expect videoPreviewFileAt(Path.combine(folder, "01.avi"), 4, 8)
    let next  = expect videoPreviewFileAt(Path.combine(folder, "02.avi"), 32, 8)
    let peer  = expect videoPreviewFileAt(Path.combine(folder, "03.avi"), 64, 8)

    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, width: ViewerWindow.MinWidth)
    defer host.shutdown()
    workspace.openScene([first, peer], .Grid2)
    openViews(&host, workspace)
    let scene    = unwrap workspace.scene()
    let document = unwrap scene.views[0].document
    let short    = unwrap ScenePlayer.from(document).film
    let long     = unwrap ScenePlayer.from(scene.views[1].document).film
    Swag.require(scene.linked and scene.links.end == .Independent)
    host.setReducedMotion(false)
    for view in scene.views
    {
        let pane = unwrap view.document
        let film = unwrap ScenePlayer.from(pane).film
        let picture = film.imageView.surfaceRect()
        pane.concealViewerBar()
        host.finishAnimations()
        pane.revealViewerBar()
        Swag.require(pane.viewerBar.isVisible() and pane.cellCaption.isVisible())
        host.advanceAnimations(0.06)
        let opacity = pane.viewerBar.presentationOpacity
        Swag.require(opacity > 0 and opacity < 1 and opacity == pane.cellCaption.presentationOpacity)
        Swag.require(pane.viewerBar.isAncestorOf(film.bottomVeil))
        Swag.require(film.surfaceRect().contains(pane.viewerBar.surfaceRect().center()))
        Swag.require(film.playButton.position.right() <= film.optionsButton.position.x)
        host.fireTimer(pane.viewerBarTimer)
        Swag.require(not pane.viewerBar.isVisible() and not pane.cellCaption.isVisible())
        host.advanceAnimations(0.03)
        let fading = pane.viewerBar.presentationOpacity
        Swag.require(fading > 0 and fading < opacity and fading == pane.cellCaption.presentationOpacity)
        pane.revealViewerBar()
        Swag.require(pane.viewerBar.presentationOpacity == fading and pane.cellCaption.presentationOpacity == fading)
        host.finishAnimations()
        pane.concealViewerBar()
        host.finishAnimations()
        Swag.require(not pane.viewerBar.isVisible() and film.imageView.surfaceRect() == picture)
    }

    var peerPoint = long.imageView.surfaceRect().center()
    host.surface.surfaceToScreen(&peerPoint)
    host.moveMouse(peerPoint)
    Swag.require(scene.views[1].document!.viewerBar.isVisible() and not document.viewerBar.isVisible())
    document.revealViewerBar()
    var point = short.playButton.surfaceRect().center()
    Swag.require(host.surfaceWnd.windowAt(point.x, point.y) == short.playButton)
    host.surface.surfaceToScreen(&point)
    host.sendMouseEvent(short.playButton, .Pressed, point, .Left, .None)
    host.sendMouseEvent(short.playButton, .Released, point, .Left, .None)
    Swag.require(short.playing and not long.playing)
    Swag.require(document.runCommand(MediaCommands.Play))
    Swag.require(short.playing and long.playing)
    short.requestPlaybackStop()
    Swag.require(not short.playing and long.playing)
    short.requestPlaybackToggle()
    Swag.require(short.playing and long.playing)
    host.sendMouseEvent(short.playButton, .DoubleClick, point, .Left, .None)
    Swag.require(not scene.maximized)
    short.elapsed = short.video.durationInSeconds()
    var wait: Time.Stopwatch
    wait.start()
    while short.playing and wait.elapsedMilliseconds() < 2_000
    {
        workspace.synchronizeMedia()
        Threading.Thread.sleep(1'ms)
    }

    Swag.require(not short.playing and long.playing and document.pendingFile.isEmpty())
    host.clickWnd(workspace.mediaPlayPause)
    Swag.require(not long.playing)

    Swag.require(document.runCommand(MediaCommands.PlayModes[2]) and workspace.scenePlayModeIs(.Folder))
    workspace.playScene()
    short.elapsed = short.video.durationInSeconds()
    wait.restart()
    while short.playing and wait.elapsedMilliseconds() < 2_000
    {
        workspace.synchronizeMedia()
        Threading.Thread.sleep(1'ms)
    }

    Swag.require(document.pendingFile == next and long.playing)
    completeQueuedViewerFile(&host, document)
    workspace.synchronizeMedia()
    Swag.require(document.currentFile == next and scene.views[0].path == next)
    Swag.require(ScenePlayer.from(document).isPlaying() and long.playing)

    workspace.setLayout(.Grid4)
    let film = unwrap ScenePlayer.from(document).film
    document.revealViewerBar()
    Swag.require(film.bottomVeil.compact and document.viewerBar.isVisible())
    Swag.require(not document.readingLine.isLocallyVisible())
    Swag.require(film.clientRect().height == document.clientRect().height)

    workspace.closeView(1)
    Swag.require(scene.layout == .Single and workspace.activeDocument() == document)
    Swag.require(not film.bottomVeil.compact and not film.sceneManaged and film.sceneViewport == {})
    Swag.require(document.readingLine.isLocallyVisible() and document.viewerBar.isVisible())
    Swag.require(not workspace.mediaLinks.isLocallyVisible() and workspace.closeFileButton.isLocallyVisible())
}

// Group commands work in a mixed grid and leave the per-view modes editable.
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    let files = [scopeTestDataPath("viewer.animation.gif"), scopeTestDataPath("viewer.png"), scopeTestDataPath("viewer.wav")]
    workspace.openScene(files, .Grid2)
    openViews(&host, workspace)
    let scene    = unwrap workspace.scene()
    let animation = unwrap scene.views[0].document
    let still     = unwrap scene.views[1].document
    let audio     = unwrap scene.views[2].document
    let picture   = assume cast(*Viewers.Picture.Panel, animation.currentView)
    let sound     = unwrap ScenePlayer.from(audio).sound
    Swag.require(picture.imageView.movie.isAnimated() and workspace.mediaTransport.isVisible() and workspace.mediaPlayPause.isVisible())

    Swag.require(animation.runCommand(MediaCommands.PlayModes[3]))
    Swag.require(workspace.scenePlayModeIs(.Shuffle))
    Swag.require(still.slideTimer and audio.playMode == .Shuffle)
    animation.setPlayMode(.Repeat)
    Swag.require(not workspace.scenePlayModeIs(.Shuffle) and not workspace.scenePlayModeIs(.Repeat))

    Swag.require(animation.runCommand(MediaCommands.Play))
    Swag.require(sound.playing and not picture.imageView.movie.isPaused and still.slideTimer)
    Swag.require(animation.runCommand(MediaCommands.Pause))
    Swag.require(not sound.playing and picture.imageView.movie.isPaused and not still.slideTimer)
    host.keyPress(.Space, .Shift)
    Swag.require(sound.playing and not picture.imageView.movie.isPaused and still.slideTimer)
    Swag.require(animation.runCommand(MediaCommands.Stop))
    Swag.require(not sound.playing and sound.playbackPosition() == 0 and not still.slideTimer)
    Swag.require(picture.imageView.movie.isPaused and picture.imageView.movie.frameIndex == 0)
}

#test
{
    for compare in [false, true]
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
        if compare
        {
            Swag.require(workspace.primary.runCommand(SceneCommands.CompareSelection))
        }
        else
        {
            explorer.grid.setFocus()
            host.keyPress(.Return)
        }

        openViews(&host, workspace)
        let scene = unwrap workspace.scene()
        Swag.require(scene.views.count == 2 and scene.compared == compare and scene.linked == compare)
        Swag.require(scene.layout == (compare ? .SideBySide : .Auto))
    }
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
