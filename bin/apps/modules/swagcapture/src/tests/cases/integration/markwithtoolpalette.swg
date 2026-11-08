#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Mark one picture with every drawing tool in the editor palette, then reopen its saved forms.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main

    var path = journey.newCapture(400, 300)
    let capture = unwrap main.editWnd.getCapture()
    journey.drawForm(ActionToolMode.Line, .Line, {10, 10}, {80, 35})
    Swag.require(Swag.kindOf(capture.forms.back()) == FormLine)

    journey.drawForm(ActionToolMode.Draw, .Draw, {110, 10}, {175, 35})
    Swag.require(Swag.kindOf(capture.forms.back()) == FormDraw)

    main.sendCommandEvent(ActionSelection.DeSelectAll)
    main.sendCommandEvent(ActionToolMode.Highlight)
    main.quickWnd.applyPreset(main.quickWnd.qsHighlight.forms[0])
    journey.drawForm(ActionToolMode.Highlight, .Highlight, {210, 10}, {285, 35})
    Swag.require(capture.forms.back().subKind == .Highlight)

    journey.drawForm(ActionToolMode.Step, .Step, {350, 25}, {350, 25})
    Swag.require(Swag.kindOf(capture.forms.back()) == FormStep)

    journey.drawForm(ActionToolMode.Text, .Text, {10, 85}, {90, 125})
    Swag.require(Swag.kindOf(capture.forms.back()) == FormText)

    journey.drawForm(ActionToolMode.Callout, .Callout, {110, 85}, {190, 125})
    Swag.require(Swag.kindOf(capture.forms.back()) == FormCallout)

    journey.drawForm(ActionToolMode.Img, .Image, {210, 85}, {290, 125})
    Swag.require(Swag.kindOf(capture.forms.back()) == FormImage)

    journey.drawForm(ActionToolMode.PixSel, .PixSel, {310, 85}, {390, 125})
    Swag.require(capture.forms.back().subKind == .PixSel)

    journey.drawForm(ActionToolMode.Favorites, .Favorites, {10, 180}, {90, 220})
    journey.drawPolygon({120, 180}, {175, 180}, {175, 225}, {120, 225})
    Swag.require(Swag.kindOf(capture.forms.back()) == FormPolygon)
    Swag.require(capture.forms.count == 10)

    main.saveCapture(capture)
    journey.openLibrary(1)
    main.libWnd.view.openItem(main.libWnd.view.items[0])
    journey.waitFor("reopen all tool marks", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and opened.forms.count == 10
    })
}
