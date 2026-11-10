#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui, Pixel, Video

// The editor exports its kept span with time-limited annotations and both sound sources.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)

    let document = testTempCapturePath()
    let source   = Capture.mediaPathOf(document, .Video)
    let exported = Gui.Testing.tempFilePath("capture-video-export-", ".mp4")
    defer
    {
        f.capture.closeMedia()
        discard catch Capture.deleteFiles(document)
    }

    defer discard catch File.delete(exported)

    let picture = Image.create(64, 48, .BGRA8)
    picture.fill(Argb.White)
    let configs: [2] Mp4.SoftwareAudioConfig = [{48_000, 1, .Voice}, {48_000, 2, .Full}]
    var recorder = expect Mp4.SoftwareRecording.createWithAudioTracks(source, 64, 48, 1_000_000, Swag.makeSlice(&configs[0], configs.count))
    for frame in 3'u64 do
        expect recorder.addFrame(&picture, FrameSlot{frame, frame * 100_000, 100_000, 0})

    var microphone: Array's16
    var system:     Array's16
    microphone.resize(14_400)
    system.resize(2 * 14_400)
    for i in microphone.count do
        microphone[i] = 1_000
    for i in system.count do
        system[i] = 2_000
    expect recorder.addAudioFrames(microphone.toSlice(), 0)
    expect recorder.addAudioFrames(system.toSlice(), 1)
    expect recorder.end()
    let sourceBytes = expect File.readAllBytes(source)

    f.capture.file = String.from(document)
    expect f.capture.adoptVideo()
    var overwrite: Swag.Error
    discard catch f.capture.exportVideo(source) as overwrite
    Swag.require(overwrite.value() != null and File.exists(source))
    let timeline = TimelineBar.create(f.main, &f.gui.root)
    timeline.panel.setPosition({0, 0, 800, TimelineHeight})
    timeline.resize(800, TimelineHeight)
    timeline.zoomAt(timeline.trackRect().horzCenter(), 2)
    var timelineImage = f.gui.render(timeline)
    Swag.require(timelineImage.isValid() and timeline.thumbsReady and timeline.thumbReader != null)

    let shape = testAddShape(f.capture, 8, 8, 20, 20)
    shape.kind      = .Rectangle
    shape.timeStart = 100_000
    shape.timeEnd   = 200_000
    f.capture.setTrim(100_000, 300_000)
    expect f.capture.showFrame(2)
    f.gui.acceptModalFileDialog(exported)
    f.main.sendCommandEvent(ActionFile.SaveAsImage)
    f.gui.pump()
    Swag.require(f.gui.autoHandled and File.exists(exported))
    Swag.require(f.capture.playhead == 2 and File.exists(source))
    let afterExport = expect File.readAllBytes(source)
    Swag.require(Slice.equals(sourceBytes.toSlice(), afterExport.toSlice()))

    var result = expect Reader.open(exported)
    Swag.require(result.frameCount() == 2 and result.audioTrackCount() == 2)
    Swag.require((unwrap result.audioTrack(0)).sampleFrameCount() == 9_600)
    Swag.require((unwrap result.audioTrack(1)).sampleFrameCount() == 9_600)
    let first = expect result.decodeFrame(0)
    Swag.require(first.pixelColor(16, 16).g < 80)
    let second = expect result.decodeFrame(1)
    Swag.require(second.pixelColor(16, 16).g > 180)
    result.close()

    // Library export gives a video its playable MP4, with the same edits and sound tracks.
    expect f.capture.save()
    let folder = Gui.Testing.tempFilePath("capture-video-folder-", "")
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)
    let library = f.setupLibraryWnd()
    expect library.exportCapture(document, folder)
    var name = String.from(Path.fileNameWithoutExtension(document) orelse "capture")
    name += ".mp4"
    let libraryVideo  = Path.combine(folder, name)
    var libraryReader = expect Reader.open(libraryVideo)
    Swag.require(libraryReader.frameCount() == 2 and libraryReader.audioTrackCount() == 2)
    libraryReader.close()

    // Copy offers the rendered video as a file, including sound, rather than a GIF or still.
    var copyState = Gui.Testing.commandState(ActionCopyPaste.CopyAsImage)
    Swag.require(Gui.Testing.actionUpdate'ActionCopyPaste(f.main, ActionCopyPaste.CopyAsImage, &copyState))
    Swag.require(copyState.name == appStrings().act_CopyVideo)
    copyState = Gui.Testing.commandState(ActionFile.CopyImage)
    Swag.require(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.CopyImage, &copyState))
    Swag.require(copyState.name == appStrings().act_CopyVideoToClipboard)
    f.main.copyLibraryImage(document)
    let copied = Clipboard.getFiles()
    Swag.require(copied.count == 1 and not Path.equals(copied[0], source))
    defer
    {
        Clipboard.clear()
        discard catch File.delete(copied[0])
    }

    var clipboardVideo = expect Reader.open(copied[0])
    Swag.require(clipboardVideo.frameCount() == 2 and clipboardVideo.audioTrackCount() == 2)
    clipboardVideo.close()
}
