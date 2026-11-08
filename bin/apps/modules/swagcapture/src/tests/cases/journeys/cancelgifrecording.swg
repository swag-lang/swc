#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Cancel a recording with frames already written and leave the library and editor untouched.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()

    let previous = journey.main.editWnd.getCapture()
    journey.recordAnimation(.Cancel)
    Swag.require(journey.main.editWnd.getCapture() == previous)

    let media = expect Directory.enumerateFiles(journey.root, CaptureMediaExtension)
    let captures = expect Directory.enumerateFiles(journey.root, CaptureFileExtension)
    Swag.require(media.isEmpty())
    for file in captures do
        Swag.require(Path.fileName(file.fullName) == "settings.scc")
}
