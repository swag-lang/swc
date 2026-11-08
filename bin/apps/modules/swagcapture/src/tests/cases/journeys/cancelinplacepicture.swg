#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Select a screen picture, then cancel its in-place editor without saving an orphan document.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let previous = journey.main.editWnd.getCapture()

    journey.cancelInPlacePicture()
    Swag.require(journey.main.editWnd.getCapture() == previous)
    let media = expect Directory.enumerateFiles(journey.root, CaptureMediaExtension)
    let captures = expect Directory.enumerateFiles(journey.root, CaptureFileExtension)
    Swag.require(media.isEmpty())
    for file in captures do
        Swag.require(Path.fileName(file.fullName) == "settings.scc")
}
