#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Audio

#test
{
    let first  = Testing.tempFilePath("scope-scroll-wrapped-", ".txt")
    let second = Testing.tempFilePath("scope-scroll-unwrapped-", ".txt")
    defer catch File.delete(first)
    defer catch File.delete(second)
    var source: String
    for index in 80
    {
        source.append(Format.toString("Line % ", index + 1))
        for 6 do
            source.append("The left side wraps its paragraph into a number of rows. ")
        source.append("\n")
    }

    discard expect File.writeAllText(first, source)
    discard expect File.writeAllText(second, source)

    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    workspace.openScene([first, second], .SideBySide)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    let left  = assume cast(*Viewers.PlainText.Panel, scene.views[0].document!.currentView)
    let right = assume cast(*Viewers.PlainText.Panel, scene.views[1].document!.currentView)
    if not left.wrapping do
        left.toggleWrap()
    if right.wrapping do
        right.toggleWrap()
    left.setZoom(145, remember: false)
    host.paint(&host.surfaceWnd)
    Swag.require(left.editor.scrollToLogicalLine(15))
    Swag.require(left.editor.topLogicalLineNumber() == 15 and right.editor.topLogicalLineNumber() == 1)

    workspace.setSceneLink(MediaCommands.Scroll, true)
    host.keyPress(.L)
    Swag.require(scene.linked)
    Swag.require(left.editor.scrollToLogicalLine(22))
    Swag.require(left.editor.topLogicalLineNumber() == 22 and right.editor.topLogicalLineNumber() == 22)
    Swag.require(left.editor.scrollPosition().y > right.editor.scrollPosition().y)
    workspace.selectView(1)
    Swag.require(right.editor.scrollToLogicalLine(10))
    Swag.require(left.editor.topLogicalLineNumber() == 10)
    Swag.require(not right.editor.scrollToLogicalLine(0) and not right.editor.scrollToLogicalLine(900))
}

#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    let files = [scopeTestDataPath("sample.svg"), scopeTestDataPath("viewer.png")]
    workspace.openScene(files, .SideBySide)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    let left  = assume cast(*Viewers.Picture.Panel, scene.views[0].document!.currentView)
    let right = assume cast(*Viewers.Picture.Panel, scene.views[1].document!.currentView)
    host.paint(&host.surfaceWnd)
    left.imageView.setZoom(left.imageView.fittedZoom() * 2)
    left.imageView.setPanOffset({20, -15})
    Swag.require(right.imageView.isFitted and right.imageView.panOffset == {})
    host.keyPress(.L)
    Swag.require(scene.linked)
    left.imageView.setPanOffset({40, -30})
    Swag.require(Math.abs(right.imageView.zoom / right.imageView.fittedZoom() - 2) < 0.001)
    let leftArea  = left.imageView.clientRect()
    let rightArea = right.imageView.clientRect()
    Swag.require(Math.abs(right.imageView.panOffset.x / rightArea.width - 40 / leftArea.width) < 0.001)
    Swag.require(Math.abs(right.imageView.panOffset.y / rightArea.height + 30 / leftArea.height) < 0.001)

    host.keyPress(.D, .Control)
    let comparison = unwrap workspace.comparison
    Swag.require(workspace.comparisonVisible() and comparison.mode == .SideBySide)
    Swag.require(workspace.activeDocument().runCommand(ComparisonCommands.ZoomIn))
    Swag.require(comparison.pictureZoom(0) == 1.25 and comparison.pictureZoom(1) == 1.25)
    workspace.setSceneLink(MediaCommands.Framing, false)
    workspace.selectView(1)
    Swag.require(workspace.activeDocument().runCommand(ComparisonCommands.ZoomIn))
    Swag.require(comparison.pictureZoom(0) == 1.25 and comparison.pictureZoom(1) == 1.5625)
    host.keyPress(.Left, .Control | .Alt)
    Swag.require(workspace.activeDocument().currentFile == (expect Path.absolute(files[1])))
    Swag.require(comparison.pictureZoom(0) == 1.5625 and comparison.pictureZoom(1) == 1.25)
    workspace.setSceneLink(MediaCommands.Framing, true)
    Swag.require(comparison.pictureZoom(0) == 1.5625 and comparison.pictureZoom(1) == 1.5625)
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
    let first  = ScenePlayer.from(scene.views[0].document)
    let second = ScenePlayer.from(scene.views[1].document)
    let step   = Math.min(first.duration(), second.duration()) / 8
    Swag.require(step > 0)

    host.keyPress(.L)
    workspace.seekScene(step)
    second.seek(step * 2)
    Swag.require(Math.abs(first.seconds() - step) < 0.002 and Math.abs(second.seconds() - step * 2) < 0.002)
    host.keyPress(.A)
    Swag.require(scene.linked and scene.links.mode == .Relative)
    Swag.require(Math.abs(scene.views[1].offset - step) < 0.002)
    workspace.seekScene(step * 3)
    Swag.require(Math.abs(first.seconds() - step * 3) < 0.002 and Math.abs(second.seconds() - step * 4) < 0.002)
    workspace.synchronizeMedia()
    let waveA = first.sound!.waveform
    let waveB = second.sound!.waveform
    Swag.require(waveA.sceneSpan == waveB.sceneSpan and waveA.sceneSpan > 0)
    Swag.require(Math.abs(waveB.sceneStart - waveA.sceneStart - cast(f32, step)) < 0.002)

    workspace.selectView(1)
    Swag.require(workspace.activeDocument().runCommand(MediaCommands.Solo))
    Swag.require(workspace.activeDocument().runCommand(MediaCommands.Times[2]))
    workspace.selectView(0)
    Swag.require(workspace.mediaLeader(scene) == 1 and workspace.audibleIndex(scene) == 1)
    Swag.require(first.sound.sceneSilent and not second.sound.sceneSilent)
    host.keyPress(.Down, .Control | .Alt)
    Swag.require(workspace.mediaLeader(scene) == 0 and workspace.audibleIndex(scene) == 0)
    Swag.require(workspace.activeDocument().currentFile == (expect Path.absolute(files[0])))

    Swag.require(workspace.activeDocument().runCommand(MediaCommands.Playback))
    Swag.require(not scene.links.playback)
    host.keyPress(.Space)
    Swag.require(first.isPlaying() and not second.isPlaying())
    host.keyPress(.Space)
    Swag.require(not first.isPlaying() and not second.isPlaying())
    Swag.require(workspace.activeDocument().runCommand(MediaCommands.Playback))
    host.keyPress(.Space)
    Swag.require(first.isPlaying() and not second.isPlaying())
    workspace.stopScene()
    host.keyPress(.Space, .Shift)
    Swag.require(first.isPlaying() and second.isPlaying())
}

func scopedAlignmentWave(path: string, delay: u32)
{
    const Rate = 8000'u32
    let frames = Rate * 3 + delay
    var bytes: Array'u8
    var writer = ByteStream.openWrite(&bytes)
    writer.writeBytes(cast(const [..] u8, "RIFF"))
    writer.writeLittleEndian(36 + frames * 2)
    writer.writeBytes(cast(const [..] u8, "WAVEfmt "))
    writer.writeLittleEndian(16'u32)
    writer.writeLittleEndian(1'u16)
    writer.writeLittleEndian(1'u16)
    writer.writeLittleEndian(Rate)
    writer.writeLittleEndian(Rate * 2)
    writer.writeLittleEndian(2'u16)
    writer.writeLittleEndian(16'u16)
    writer.writeBytes(cast(const [..] u8, "data"))
    writer.writeLittleEndian(frames * 2)
    for delay do
        writer.writeLittleEndian(0's16)
    for index in Rate * 3
    {
        let t         = cast(f64, index) / 8
        let amplitude = 3000 + 1500 * Math.sin(t * 0.0321) + 1400 * Math.cos(t * 0.0779) * Math.sin(t * 0.012)
        writer.writeLittleEndian(cast(s16, amplitude * Math.sin(t * 1.94)))
    }

    expect File.writeAllBytes(path, bytes.toSlice())
}

#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    let first  = Testing.tempFilePath("scope-audio-reference-", ".wav")
    let second = Testing.tempFilePath("scope-audio-delayed-", ".wav")
    defer catch File.delete(first)
    defer catch File.delete(second)
    scopedAlignmentWave(first, 0)
    scopedAlignmentWave(second, 1_384)

    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    workspace.openScene([first, second], .Stacked)
    openViews(&host, workspace)
    let scene  = unwrap workspace.scene()
    let leader = ScenePlayer.from(scene.views[0].document)
    let other  = ScenePlayer.from(scene.views[1].document)
    Swag.require(workspace.activeDocument().runCommand(MediaCommands.AlignSound))
    workspace.alignSound.task.wait()
    host.pump()
    Swag.require(scene.linked and scene.links.mode == .Relative)
    Swag.require(Math.abs(scene.views[1].offset - 0.173) < 0.003)
    workspace.seekScene(0.5)
    Swag.require(Math.abs(other.seconds() - 0.673) < 0.003)

    workspace.setSceneLink(MediaCommands.Playback, false)
    workspace.setSceneLink(MediaCommands.Linked, false)
    Swag.require(workspace.activeDocument().runCommand(MediaCommands.Ends[2]))
    Swag.require(workspace.usesLinkedTransport(scene))
    workspace.setSceneLink(MediaCommands.Linked, false)
    Swag.require(workspace.activeDocument().sendComputeCommandStateEvent(MediaCommands.Ends[1]).checked)
    Swag.require(not workspace.activeDocument().sendComputeCommandStateEvent(MediaCommands.Ends[2]).checked)
    Swag.require(workspace.activeDocument().runCommand(MediaCommands.Ends[2]))
    workspace.seekScene(leader.duration())
    workspace.synchronizeMedia()
    Swag.require(not leader.isPlaying() and not other.isPlaying())
    Swag.require(Math.abs(leader.seconds() - leader.duration()) < 0.003)
    Swag.require(not leader.sound!.backHistory.isEmpty() and Math.abs(leader.sound.backHistory.back() - 0.5) < 0.003)

    workspace.openDocument(scopeTestDataPath("sample.cpp"))
    openViews(&host, workspace)
    workspace.selectScene(0)
    openViews(&host, workspace)
    let document = workspace.activeDocument()
    for 8 where document.readingState.restoring
    {
        Swag.drainWork()
        host.pump()
        host.fireTimers()
    }

    let restored = unwrap ScenePlayer.from(document).sound
    Swag.require(not document.readingState.restoring, "sound reading state did not settle")
    Swag.require(not restored.backHistory.isEmpty())
    restored.navigateBack()
    Swag.require(Math.abs(restored.playbackPosition() - 0.5) < 0.003)
}

#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    let path = scopeTestDataPath("document-outline.pdf")
    workspace.openScene([path, path], .SideBySide)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    let first = assume cast(*Viewers.PdfDocument.Panel, scene.views[0].document!.currentView)
    let other = assume cast(*Viewers.PdfDocument.Panel, scene.views[1].document!.currentView)
    workspace.setSceneLink(MediaCommands.Scroll, true)
    first.pdfView.showPage(1)
    Swag.require(first.pdfView.pageIndex == 1 and other.pdfView.pageIndex == 0)
    host.keyPress(.L)
    Swag.require(other.pdfView.pageIndex == 1)
    first.pdfView.setPageLayout(.Single)
    other.pdfView.setPageLayout(.Single)
    workspace.selectView(1)
    other.pdfView.showPage(2)
    Swag.require(first.pdfView.pageIndex == 2)
}

// The waveform and transport seek the same linked clock in either orientation.
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, width: ViewerWindow.MinWidth, height: 480)
    defer host.shutdown()
    workspace.openScene([scopeTestDataPath("pacman_beginning.wav"), scopeTestDataPath("viewer.wav")], .SideBySide)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    let first = unwrap ScenePlayer.from(scene.views[0].document).sound
    let other = unwrap ScenePlayer.from(scene.views[1].document).sound
    workspace.setSceneLink(MediaCommands.Linked, true)
    first.timeline.setValueWithoutGesture(0.25)
    first.timeline.sigEndChange.call(first.timeline)
    Swag.require(Math.abs(other.playbackPosition() - 0.25) < 0.02)
    first.jumpTo(0)
    host.clickWnd(first.waveform)
    Swag.require(other.playbackPosition() > 0.1)

    workspace.setLayout(.Grid4)
    let layout = first.pageLayout()
    Swag.require(layout.cover.y >= 0 and layout.cover.bottom() <= layout.titleTop)
    Swag.require(first.waveform.position.bottom() <= first.clientRect().bottom())
    Swag.require(first.compactTransport and first.optionsButton.isLocallyVisible())
    Swag.require(first.playButton.position.right() <= first.timeline.position.x and first.timeline.position.width > 0)
    Swag.require(first.timeline.position.right() <= first.optionsButton.position.x)
    host.activateOptionRowWhenShown(appStrings().ui_PlayMode)
    host.thenActivateOptionRow(Viewer.playModeText(.Repeat))
    first.optionsButton.sigPressed.call(first.optionsButton)
    Swag.require(scene.views[0].document!.playMode == .Repeat)
    workspace.closeView(1)
    Swag.require(not first.compactTransport and first.playModeButton.isLocallyVisible())
    Swag.require(first.timeline.position.bottom() <= first.playButton.position.y)
}
