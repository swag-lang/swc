#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Edit a dense grid through the pointer, undo and redo its full history, then replace its tail.
#[Swag.TestTag("stress")]
#test
{
    var fixture: HeadlessFixture
    fixture.setup()
    defer fixture.shutdown()
    let capture = fixture.capture

    for index in 128
    {
        let x = 10 + cast(f32, index % 16) * 23
        let y = 10 + cast(f32, index / 16) * 25
        fixture.main.editMode = .Shape
        fixture.dragImage({x, y}, {x + 16, y + 12})
    }
    Swag.require(capture.forms.count == 128 and capture.undoMgr.appliedCount() == 128)
    var image = fixture.gui.render(fixture.main)
    Swag.require(image.isValid())

    for index in 128
    {
        capture.undo()
        Swag.require(capture.forms.count == 127 - index)
    }
    Swag.require(not capture.canUndo() and capture.canRedo())
    for index in 128
    {
        capture.redo()
        Swag.require(capture.forms.count == index + 1)
    }
    Swag.require(capture.canUndo() and not capture.canRedo())

    for 64 do
        capture.undo()
    fixture.main.editMode = .Shape
    fixture.dragImage({12, 210}, {28, 224})
    Swag.require(capture.forms.count == 65 and capture.undoMgr.count() == 65)
    Swag.require(not capture.canRedo())
    image = fixture.gui.render(fixture.main)
    Swag.require(image.isValid())
}
