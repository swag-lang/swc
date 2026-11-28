#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Video

// A producer failure before its first frame stops the recorder and preserves its cause.
#[Swag.TestTag("record.failure")]
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    var recorder: Recorder
    recorder.main      = f.main
    recorder.videoMode = true
    recorder.state     = .Recording
    catch { fail Errors.BadParameterError{"video producer test failure"} }
    {
        recorder.videoProducer.error.capture(Swag.err)
    }

    Atomic.exchange(&recorder.videoProducer.failed, 1)

    recorder.advance()

    Swag.require(recorder.state == .Stopped)
    Swag.require(recorder.recordError.value() is Errors.BadParameterError)
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
    let capture = Memory.new!{Capture}()
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
    var area    = evenVideoArea({100, 50, 2664 - 2001, 1079 - 600}, desktop)
    Swag.require(area.x == 100 and area.y == 50 and area.width == 664 and area.height == 480)

    area = evenVideoArea({100, 50, 640, 360}, desktop)
    Swag.require(area.width == 640 and area.height == 360)

    // Against the right and bottom edges there is no pixel left to take.
    area = evenVideoArea({1257, 579, 663, 501}, desktop)
    Swag.require(area.x == 1257 and area.y == 579 and area.width == 662 and area.height == 500)

    let recorded = VideoCaptureSession.pictureSize({0, 0, 7680, 2160})
    Swag.require(recorded.width == 4096 and recorded.height == 1152)
}
