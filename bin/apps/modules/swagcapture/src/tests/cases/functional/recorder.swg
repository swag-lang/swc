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
    let exported = Gui.Testing.tempFilePath("capture-video-", ".mp4")
    defer discard catch File.delete(exported)
    f.main.doSaveAsImage(exported)
    Swag.require(File.exists(exported))
    let originalBytes = expect File.readAllBytes(file)
    let exportedBytes = expect File.readAllBytes(exported)
    Swag.require(Slice.equals(originalBytes.toSlice(), exportedBytes.toSlice()))
    var copy = expect Reader.open(exported)
    Swag.require(copy.frameCount() == owned.timeline.frameCount)
    copy.close()
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
}
