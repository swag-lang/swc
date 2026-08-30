#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Pixel selection fill and clear mutate only through undoable image replacement.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    f.capture.width   = 30
    f.capture.height  = 30
    f.capture.backImg = Image.create(30, 30, .BGRA8)
    f.capture.backImg.fill(Argb.Zero)

    let pixSel = testAddShape(f.capture, 5, 5, 10, 10, .PixSel)
    pixSel.kind = .Rectangle
    f.capture.selection.add(0)

    f.main.pixSelFillCol = ColorRed
    f.main.sendCommandEvent(ActionPixSel.Fill)
    let filledBytes = Gui.Testing.countNonZeroBytes(f.capture.backImg)
    Swag.assert(filledBytes > 0)
    Swag.assert(f.capture.canUndo())

    f.capture.undo()
    Swag.assert(Gui.Testing.countNonZeroBytes(f.capture.backImg) == 0)

    f.capture.redo()
    Swag.assert(Gui.Testing.countNonZeroBytes(f.capture.backImg) == filledBytes)

    f.main.sendCommandEvent(ActionPixSel.Clear)
    Swag.assert(Gui.Testing.countNonZeroBytes(f.capture.backImg) == 0)

    f.capture.undo()
    Swag.assert(Gui.Testing.countNonZeroBytes(f.capture.backImg) == filledBytes)
}

// Smart fill uses surrounding pixels to replace a pixel-selection area and remains undoable.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    f.capture.width   = 24
    f.capture.height  = 24
    f.capture.backImg = Image.create(24, 24, .BGRA8)
    f.capture.backImg.visitPixels()
    {
        let r = cast(u8) ((x * 17 + y * 3) % 255)
        let g = cast(u8) ((x * 5 + y * 19) % 255)
        let b = cast(u8) ((x * 29 + y * 7) % 255)
        pix[as u32] = Color.fromArgb(255'u8, r, g, b).argb
    }

    let before = f.capture.backImg.pixelColor(12, 12)
    let pixSel = testAddShape(f.capture, 6, 6, 12, 12, .PixSel)
    pixSel.kind = .Rectangle
    f.capture.selection.add(0)

    f.main.sendCommandEvent(ActionPixSel.SmartFill)
    let after = f.capture.backImg.pixelColor(12, 12)
    Swag.assert(after.argb != before.argb)

    f.capture.undo()
    Swag.assert(f.capture.backImg.pixelColor(12, 12).argb == before.argb)

    f.capture.redo()
    Swag.assert(f.capture.backImg.pixelColor(12, 12).argb == after.argb)
}

// Smart move captures a pixel selection into a movable image form, then deletes the
// original selection as one undoable operation. This exercises renderer-backed
// texture creation in the GUI headless host.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    f.capture.width   = 24
    f.capture.height  = 24
    f.capture.backImg = Gui.Testing.indexedImage(24, 24)

    let before = f.capture.backImg.pixelColor(12, 12)
    let pixSel = testAddShape(f.capture, 6, 6, 12, 12, .PixSel)
    pixSel.kind = .Rectangle
    f.capture.selection.add(0)

    f.main.sendCommandEvent(ActionPixSel.SmartMove)

    Swag.assert(f.capture.forms.count == 1)
    Swag.assert(f.capture.selection.count == 1)
    Swag.assert(f.capture.selection[0] == 0)
    Swag.assert(Swag.kindOf(f.capture.forms[0]) == FormImage)

    let imgForm = cast(*FormImage) f.capture.forms[0].buffer
    Swag.assert(imgForm.kind == .Capture)
    Swag.assert(imgForm.image.isValid())
    Swag.assert(imgForm.image.width == 12)
    Swag.assert(imgForm.image.height == 12)
    Swag.assert(imgForm.texture.isValid())
    Swag.assert(f.capture.backImg.pixelColor(12, 12).argb != before.argb)

    f.capture.undo()
    Swag.assert(f.capture.forms.count == 1)
    Swag.assert(Swag.kindOf(f.capture.forms[0]) == FormShape)
    Swag.assert(f.capture.backImg.pixelColor(12, 12).argb == before.argb)

    f.capture.redo()
    Swag.assert(f.capture.forms.count == 1)
    Swag.assert(Swag.kindOf(f.capture.forms[0]) == FormImage)
}

// Pixel-selection extraction filters the current selection without rendering.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let pixSel = testAddShape(f.capture, 4, 4, 10, 10, .PixSel)
    pixSel.kind = .Rectangle
    discard testAddText(f.capture, 20, 4, 10, 10)
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    let pixSels = f.main.getPixSels()
    Swag.assert(pixSels.count == 1)
    Swag.assert(pixSels[0].buffer == pixSel)
}
