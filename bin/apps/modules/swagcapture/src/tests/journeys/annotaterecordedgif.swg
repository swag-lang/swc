#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Put an annotation on later recording frames and export a GIF that really changes over time.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    journey.recordAnimation(.Stop)
    let main = journey.main
    let capture = unwrap main.editWnd.getCapture()
    var path = String.from(capture.file)

    journey.drawForm(ActionToolMode.Arrow, .Arrow, {5, 5}, {45, 30})
    main.sendCommandEvent(ActionToolMode.Selection)
    main.sendCommandEvent(ActionSelection.SelectAll)
    Swag.require(capture.selection.count == 1)
    main.sendCommandEvent(ActionTimeline.NextFrame)
    Swag.require(capture.playhead == 1)
    main.sendCommandEvent(ActionTimeline.ShowFrom)
    let start = capture.forms[0].timeStart
    Swag.require(start > 0)
    main.sendCommandEvent(ActionTimeline.PrevFrame)
    Swag.require(not capture.isFormShown(capture.forms[0]))

    let exportFolder = Path.combine(journey.root, "exports")
    expect Directory.create(exportFolder)
    let gif = Path.combine(exportFolder, "annotated.gif")
    expect capture.exportAnimation(gif)
    let bytes = expect File.readAllBytes(gif)
    var reader = expect ImageReader.decode("annotated.gif", bytes.toSlice())
    Swag.require(reader.info.frames.count >= 2)

    main.saveCapture(capture)
    journey.openLibrary(1)
    main.libWnd.view.openItem(main.libWnd.view.items[0])
    journey.waitFor("timed annotation reopened", func|main, &path, start|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and
               opened.forms.count == 1 and opened.forms[0].timeStart == start and not opened.mediaMissing
    })
}
