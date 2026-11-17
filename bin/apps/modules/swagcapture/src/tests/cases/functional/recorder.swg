#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Video

// Frames left before the recording in progress ends, and whether it ends by a cancel.
var g_TestFramesLeft:  u32
var g_TestCancelAtEnd: bool
var g_TestSawPreparation: bool

// Ends the recording in progress once `frames` frames have run. The caller clears the frame
// callbacks of the application with [[testEndRecording]].
internal func testEndRecordingAfter(frames: u32, cancel: bool)
{
    g_TestFramesLeft  = frames
    g_TestCancelAtEnd = cancel
    g_App.sigFrame    += func(_)
    {
        if g_TestFramesLeft == 0 do
            return
        if g_Recorder and g_Recorder!.videoMode and not g_Recorder!.videoProducer.hasOrigin() do
            return
        g_TestFramesLeft -= 1
        if g_TestFramesLeft != 0 or not g_Recorder do
            return
        if g_TestCancelAtEnd do
            g_Recorder!.cancel()
        else do
            g_Recorder!.stop()
    }
}

// Starts a video from its live preparation, then ends it after a few frame callbacks.
internal func testStartAndEndVideoAfter(frames: u32)
{
    g_TestFramesLeft     = frames
    g_TestSawPreparation = false
    g_App.sigFrame += func(_)
    {
        if not g_Recorder do
            return
        if g_Recorder!.state == .Preparing
        {
            g_TestSawPreparation = true
            g_Recorder!.recordRequested = true
            return
        }
        if not g_Recorder!.videoProducer.hasOrigin() do
            return
        if g_TestFramesLeft do
            g_TestFramesLeft -= 1
        if not g_TestFramesLeft do
            g_Recorder!.stop()
    }
}

// Lets the application destroy the recording frame and pill, and forgets the frame callbacks.
internal func testEndRecording()
{
    g_App.runFrame()
    g_App.sigFrame.clear()
}

// A stopped recording becomes an animation capture over a frame file named after it, and the
// command that started it is the one that stops it.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    testEndRecordingAfter(20, cancel: false)
    let capture = expect Recorder.record(f.main, {0, 0, 64, 48})
    testEndRecording()
    Swag.require(capture != null)
    Swag.require(g_Recorder == null)

    let file = String.from(capture.file)
    defer catch Capture.deleteFiles(file)
    defer Memory.delete(capture)

    Swag.require(capture.media == .Animation and capture.sourceKind == .Screen)
    Swag.require(capture.width == 64 and capture.height == 48)
    Swag.require(capture.timeline.frameCount >= 1)
    Swag.require(File.exists(Capture.mediaPathOf(file)))
}

// Recording options choose the next take's cadence, limit and stored dimensions.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    f.main.captureOptions.recordRate         = .Fps20
    f.main.captureOptions.recordMaxSeconds    = 60
    f.main.captureOptions.recordMaxDimension  = 320
    testEndRecordingAfter(20, cancel: false)
    let capture = expect Recorder.record(f.main, {0, 0, 640, 480})
    testEndRecording()
    Swag.require(capture != null)

    let file = String.from(capture.file)
    defer catch Capture.deleteFiles(file)
    defer Memory.delete(capture)
    Swag.require(capture.width == 320 and capture.height == 240)
    Swag.require(capture.timeline.duration <= 60_000_000)
}

// The video command writes a playable MP4, and its capture reopens with an indexed timeline.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()

    let before = f.main.savedPaths.count
    testEndRecordingAfter(20, cancel: false)
    let capture = expect Recorder.recordVideo(f.main, CaptureTarget.create({0, 0, 64, 48}, 0))
    testEndRecording()
    let owned = unwrap capture
    Swag.require(owned.media == .Video)
    Swag.require(g_Recorder == null and f.main.savedPaths.count == before + 1)

    let file = f.main.savedPaths[before]
    let document = String.from(owned.file)
    defer catch Capture.deleteFiles(document)
    defer Memory.delete(owned)
    Swag.require(File.exists(file))
    Swag.require(owned.timeline.frameCount >= 1 and owned.frames != null)
    var reader = expect Reader.open(file)
    Swag.require(reader.frameCount() >= 1)
    var picture: Pixel.Image
    expect reader.decodeFrameInto(&picture, 0)
    Swag.require(picture.width == 64 and picture.height == 48)
    reader.close()

    owned.changed = true
    expect owned.save()
    owned.title = "Unsaved video copy"
    owned.linkedImage = Gui.Testing.tempFilePath("capture-linked-video-", ".png")
    owned.changed = true
    let duplicatePath = Library.newFileName()
    defer discard catch Capture.deleteFiles(duplicatePath)
    let snapshot = expect owned.snapshotDuplicate(duplicatePath)
    defer Memory.delete(snapshot)
    expect Capture.duplicateSnapshot(document, snapshot)
    let duplicate = expect Capture.load(duplicatePath)
    defer Memory.delete(duplicate)
    Swag.require(duplicate.title == "Unsaved video copy" and duplicate.linkedImage.isEmpty())
    Swag.require(duplicate.media == .Video and duplicate.timeline.frameCount == owned.timeline.frameCount)
    let duplicateMedia = expect File.readAllBytes(Capture.mediaPathOf(duplicatePath, .Video))
    let sourceMedia = expect File.readAllBytes(file)
    Swag.require(Slice.equals(duplicateMedia.toSlice(), sourceMedia.toSlice()))
    let loaded = expect Capture.load(document)
    defer Memory.delete(loaded)
    Swag.require(loaded.media == .Video and loaded.frames != null)
    Swag.require(loaded.timeline.frameCount == owned.timeline.frameCount)
    expect loaded.showFrame(0)
    Swag.require(loaded.backImg.width == 64 and loaded.backImg.height == 48)

    // The editor's save action offers the original MP4 as a playable standalone file.
    f.capture.media = .Video
    f.capture.file = String.from(document)
    expect f.capture.adoptVideo()
    var state = Gui.Testing.commandState(ActionFile.SaveAsImage)
    Swag.require(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.SaveAsImage, &state))
    Swag.require(state.longName == appStrings().act_SaveAsVideo)
    state = Gui.Testing.commandState(ActionFile.SaveAsLinkedImage)
    Swag.require(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.SaveAsLinkedImage, &state))
    Swag.require(state.disabled)

    // A video is linked to the MP4 beside its document, and the location command goes there.
    Swag.require(f.capture.linkedImage.isEmpty())
    Swag.require(f.capture.linkedFile() == Capture.mediaPathOf(document, .Video))
    state = Gui.Testing.commandState(ActionFile.LinkedFileLocation)
    Swag.require(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.LinkedFileLocation, &state))
    Swag.require(not state.disabled and state.name == appStrings().act_LocateLinkedVideo)
    f.capture.mediaMissing = true
    state = Gui.Testing.commandState(ActionFile.LinkedFileLocation)
    Swag.require(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.LinkedFileLocation, &state))
    Swag.require(state.disabled and f.capture.linkedFile().isEmpty())
    f.capture.mediaMissing = false
    let exported = Gui.Testing.tempFilePath("capture-video-", ".mp4")
    defer discard catch File.delete(exported)
    f.main.doSaveAsImage(exported)
    Swag.require(f.main.videoCopyJobs.count == 1)
    f.main.videoCopyJobs[0].task.wait()
    f.gui.pump()
    Swag.require(File.exists(exported))
    let originalBytes = expect File.readAllBytes(file)
    let exportedBytes = expect File.readAllBytes(exported)
    Swag.require(Slice.equals(originalBytes.toSlice(), exportedBytes.toSlice()))
    var copy = expect Reader.open(exported)
    Swag.require(copy.frameCount() == owned.timeline.frameCount)
    copy.close()

    let libraryExport = Gui.Testing.tempFilePath("capture-library-video-", ".mp4")
    defer discard catch File.delete(libraryExport)
    f.main.requestLibraryExport(document, libraryExport, false)
    Swag.require(f.main.exportJob != null)
    f.main.exportJob.task.wait()
    f.gui.pump()
    Swag.require(f.main.videoCopyJobs.count == 1)
    f.main.videoCopyJobs[0].task.wait()
    f.gui.pump()
    Swag.require(File.exists(libraryExport))
    let libraryBytes = expect File.readAllBytes(libraryExport)
    Swag.require(Slice.equals(originalBytes.toSlice(), libraryBytes.toSlice()))

    let folder = Gui.Testing.tempFilePath("capture-selected-video-", "")
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)
    let library = f.setupLibraryWnd()
    var selected: Array'String
    selected.add(document)
    library.beginExport(#move selected, folder)
    Swag.require(library.exportJob != null)
    library.exportJob.task.wait()
    f.gui.pump()
    Swag.require(library.videoCopyJob != null and library.exporting)
    library.videoCopyJob.task.wait()
    f.gui.pump()
    Swag.require(not library.exporting and library.videoCopyJob == null)
    let selectedPath = Path.combine(folder, Format.toString("%.mp4", Path.fileNameWithoutExtension(document) orelse "capture"))
    let selectedBytes = expect File.readAllBytes(selectedPath)
    Swag.require(Slice.equals(originalBytes.toSlice(), selectedBytes.toSlice()))
}

// A cancelled recording keeps nothing.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    let before = expect Directory.enumerateFiles(Library.getFolder(), CaptureMediaExtension)
    testEndRecordingAfter(5, cancel: true)
    let capture = expect Recorder.record(f.main, {0, 0, 64, 48})
    testEndRecording()
    Swag.require(capture == null)

    let after = expect Directory.enumerateFiles(Library.getFolder(), CaptureMediaExtension)
    Swag.require(after.count == before.count)
}

// A late recording failure keeps the completed video prefix as an editable capture.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    let before = f.main.savedPaths.count
    testEndRecordingAfter(20, cancel: false)
    g_App.sigFrame += func(_)
    {
        if g_Recorder and g_Recorder!.state == .Stopped do
            g_Recorder!.writeFailed = true
    }
    let capture = expect Recorder.recordVideo(f.main, CaptureTarget.create({0, 0, 64, 48}, 0))
    testEndRecording()
    let kept = unwrap capture
    defer Memory.delete(kept)
    let file = String.from(kept.file)
    defer discard catch Capture.deleteFiles(file)
    Swag.require(kept.timeline.frameCount > 0 and not kept.mediaMissing)
    Swag.require(f.main.savedPaths.count == before + 1)
    Swag.require(File.exists(Capture.mediaPathOf(file, .Video)))

    kept.changed = true
    expect kept.save()
    let reopened = expect Capture.load(file)
    defer Memory.delete(reopened)
    Swag.require(reopened.timeline.frameCount == kept.timeline.frameCount and not reopened.mediaMissing)
}

// The video preparation waits for Record, then creates an MP4 from the live target.
#[Swag.TestTag("record.preparation")]
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()

    testStartAndEndVideoAfter(20)

    let capture = expect Recorder.recordVideo(f.main, CaptureTarget.create({0, 0, 64, 48}, 0), prepare: true)
    testEndRecording()
    Swag.require(g_TestSawPreparation and not g_TestFramesLeft)
    let owned = unwrap capture
    Swag.require(owned.media == .Video and owned.timeline.frameCount >= 1)
    let file = String.from(owned.file)
    defer catch Capture.deleteFiles(file)
    defer Memory.delete(owned)
    Swag.require(File.exists(Capture.mediaPathOf(file, .Video)))
}

// Cancelling a video removes its partial MP4 and does not create a capture document.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    let before = expect Directory.enumerateFiles(Library.getFolder(), CaptureVideoExtension)
    testEndRecordingAfter(5, cancel: true)
    let capture = expect Recorder.recordVideo(f.main, CaptureTarget.create({0, 0, 64, 48}, 0))
    testEndRecording()
    Swag.require(capture == null)

    let after = expect Directory.enumerateFiles(Library.getFolder(), CaptureVideoExtension)
    Swag.require(after.count == before.count)
}

// The pill and the timeline write minutes and two-digit seconds, the timeline with the tenth.
#test
{
    Swag.require(Capture.clockText(0) == "0:00")
    Swag.require(Capture.clockText(67_000_000) == "1:07")
    Swag.require(Capture.clockText(3_727_000_000) == "1:02:07")
    Swag.require(Capture.clockText(3_450_000, tenths: true) == "0:03.4")
    Swag.require(Capture.clockText(12_000_000) == "0:12")
    Swag.require(Capture.clockText(4_259_950_000, tenths: true) == "1:10:59.9")
    Swag.require(Capture.clockText(36_000_000_000) == "10:00:00")
}

// A recording keeps the identity of the window it was taken from, as a screenshot does.
#test
{
    let capture = Memory.new'Capture()
    defer Memory.delete(capture)

    with var window: CaptureWindowInfo
    {
        .application  = "Editor"
        .executable   = "editor.exe"
        .title        = "notes.txt"
        .className    = "EditorFrame"
        .nativeWindow = 42
    }

    capture.setScreenSource(window)
    Swag.require(capture.sourceKind == .Screen)
    Swag.require(capture.sourceApplication == "Editor" and capture.sourceExecutable == "editor.exe")
    Swag.require(capture.sourceWindowTitle == "notes.txt" and capture.sourceWindowClass == "EditorFrame")
}

// A video records even sides without dropping the last column or row of the selection: an odd
// side takes one pixel more, and gives one up only against the far edge of the desktop.
#test
{
    let desktop = Math.Rectangle{0, 0, 1920, 1080}
    var area = evenVideoArea({100, 50, 2664 - 2001, 1079 - 600}, desktop)
    Swag.require(area.x == 100 and area.y == 50 and area.width == 664 and area.height == 480)

    area = evenVideoArea({100, 50, 640, 360}, desktop)
    Swag.require(area.width == 640 and area.height == 360)

    // Against the right and bottom edges there is no pixel left to take.
    area = evenVideoArea({1257, 579, 663, 501}, desktop)
    Swag.require(area.x == 1257 and area.y == 579 and area.width == 662 and area.height == 500)

    let recorded = VideoCaptureSession.pictureSize({0, 0, 7680, 2160})
    Swag.require(recorded.width == 4096 and recorded.height == 1152)
}
