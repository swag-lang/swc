#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// A densely marked picture remains renderable while all marks are selected and the zoom changes.
#[Swag.TestTag("stress")]
#test
{
    var fixture: HeadlessFixture
    fixture.setup()
    defer fixture.shutdown()

    for row in 20
    {
        for column in 16
        {
            let x = 8 + cast(f32, column) * 24
            let y = 8 + cast(f32, row) * 14
            discard testAddShape(fixture.capture, x, y, 18, 10)
        }
    }
    Swag.require(fixture.capture.forms.count == 320)

    for index in fixture.capture.forms.count do
        fixture.capture.selection.add(index)
    fixture.capture.selectionHasChanged()
    Swag.require(fixture.capture.selection.count == 320)

    for zoom in [0.5'f32, 1.0, 2.0]
    {
        fixture.editView.setZoom(zoom)
        fixture.gui.fireTimer(fixture.editView.zoomTimer)
        var image = fixture.gui.render(fixture.main)
        Swag.require(image.isValid())
        Swag.require(fixture.capture.forms.count == 320 and fixture.capture.selection.count == 320)
    }
}
