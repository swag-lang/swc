#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Pause a GIF recording from its pill, resume it, then stop after another frame is written.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    journey.recordAnimation(.PauseThenStop)

    let capture = unwrap journey.main.editWnd.getCapture()
    Swag.require(capture.media == .Animation and capture.timeline.frameCount >= 2)
    Swag.require(File.exists(capture.file) and File.exists(Capture.mediaPathOf(capture.file)))
}
