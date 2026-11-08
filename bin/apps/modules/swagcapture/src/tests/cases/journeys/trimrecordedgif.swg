#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Trim a newly recorded animation through timeline commands, reopen it and export the kept span.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    journey.recordAnimation(.Stop)
    let main = journey.main
    let capture = unwrap main.editWnd.getCapture()
    var path = String.from(capture.file)

    main.sendCommandEvent(ActionTimeline.NextFrame)
    Swag.require(capture.playhead == 1)
    main.sendCommandEvent(ActionTimeline.TrimStart)
    let start = capture.trimStart()
    Swag.require(start > 0 and capture.isTrimmed())
    main.saveCapture(capture)

    journey.openLibrary(1)
    main.libWnd.view.openItem(main.libWnd.view.items[0])
    journey.waitFor("trimmed recording reopened", func|main, &path, start|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and
               opened.isTimed() and opened.trimStart() == start and not opened.mediaMissing
    })

    let opened = unwrap main.editWnd.getCapture()
    let gif = Path.combine(journey.root, "trimmed.gif")
    expect opened.exportAnimation(gif)
    let bytes = expect File.readAllBytes(gif)
    var reader = expect ImageReader.decode("trimmed.gif", bytes.toSlice())
    Swag.require(reader.info.frames.count >= 1)

    main.sendCommandEvent(ActionTimeline.KeepAll)
    Swag.require(not opened.isTrimmed())
    main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(opened.trimStart() == start)
}
