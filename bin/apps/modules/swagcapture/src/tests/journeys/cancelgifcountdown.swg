#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Cancel from the recording pill during the countdown, before any frame or capture is kept.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let previous = journey.main.editWnd.getCapture()

    journey.recordAnimation(.CancelCountdown)
    Swag.require(journey.main.editWnd.getCapture() == previous)
    let media = expect Directory.enumerateFiles(journey.root, CaptureMediaExtension)
    Swag.require(media.isEmpty())
}
