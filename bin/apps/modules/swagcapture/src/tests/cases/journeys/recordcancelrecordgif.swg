#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Record, cancel a second take, then record again without leaving the editor.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main

    journey.recordAnimation(.Stop)
    let first = unwrap main.editWnd.getCapture()
    var firstPath = String.from(first.file)
    Swag.require(first.isTimed() and File.exists(firstPath))

    journey.recordAnimation(.Cancel)
    Swag.require(g_Recorder == null and journey.app.surfaces.count == 1)
    journey.recordAnimation(.Stop)
    let last = unwrap main.editWnd.getCapture()
    var lastPath = String.from(last.file)
    Swag.require(last.isTimed() and lastPath != firstPath and File.exists(lastPath))

    journey.openLibrary(2)
    var foundFirst, foundLast: bool
    for item in main.libWnd.view.items
    {
        if item.fi.fullName == firstPath do
            foundFirst = true
        if item.fi.fullName == lastPath do
            foundLast = true
    }
    Swag.require(foundFirst and foundLast)
}
