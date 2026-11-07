#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Frames left before the recording in progress ends, and whether it ends by a cancel.
var g_TestFramesLeft:  u32
var g_TestCancelAtEnd: bool

// Ends the recording in progress once `frames` frames have run. The caller clears the frame
// callbacks of the application with [[testEndRecording]].
func testEndRecordingAfter(frames: u32, cancel: bool)
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

// Lets the application destroy the recording frame and pill, and forgets the frame callbacks.
func testEndRecording()
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
