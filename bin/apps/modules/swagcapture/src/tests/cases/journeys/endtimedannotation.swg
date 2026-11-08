#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// End an annotation on a GIF frame, trim the tail, and reopen both timing edits.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    journey.recordAnimation(.Stop)
    let main = journey.main
    let capture = unwrap main.editWnd.getCapture()
    var path = String.from(capture.file)

    journey.drawForm(ActionToolMode.Shape, .Shape, {8, 8}, {55, 40})
    main.sendCommandEvent(ActionToolMode.Selection)
    main.sendCommandEvent(ActionSelection.SelectAll)
    main.sendCommandEvent(ActionTimeline.NextFrame)
    Swag.require(capture.playhead == 1)
    main.sendCommandEvent(ActionTimeline.ShowUntil)
    let end = capture.forms[0].timeEnd
    Swag.require(end > 0 and not capture.isFormShown(capture.forms[0]))
    main.sendCommandEvent(ActionTimeline.PrevFrame)
    Swag.require(capture.isFormShown(capture.forms[0]))

    main.sendCommandEvent(ActionTimeline.NextFrame)
    main.sendCommandEvent(ActionTimeline.TrimEnd)
    let trim = capture.trimEnd()
    Swag.require(capture.isTrimmed() and trim == end and trim < capture.timeline.duration)
    main.saveCapture(capture)
    journey.openLibrary(1)
    main.libWnd.view.openItem(main.libWnd.view.items[0])
    journey.waitFor("timed ending reopened", func|main, &path, end, trim|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and
               opened.forms.count == 1 and opened.forms[0].timeEnd == end and opened.trimEnd() == trim
    })

    let opened = unwrap main.editWnd.getCapture()
    main.sendCommandEvent(ActionSelection.SelectAll)
    main.sendCommandEvent(ActionTimeline.ShowAlways)
    Swag.require(opened.forms[0].timeEnd == 0)
    main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(opened.forms[0].timeEnd == end)
}
