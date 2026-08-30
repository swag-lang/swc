#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Image actions that do not open dialogs mutate the backing image in memory and
// remain undoable through the normal action path.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    f.capture.width   = 4
    f.capture.height  = 3
    f.capture.backImg = Gui.Testing.indexedImage(4, 3)

    let before00 = f.capture.backImg.pixelColor(0, 0)
    let before30 = f.capture.backImg.pixelColor(3, 0)
    let before02 = f.capture.backImg.pixelColor(0, 2)

    f.main.sendCommandEvent(ActionImage.MirrorImage)
    Swag.assert(f.capture.backImg.pixelColor(0, 0).argb == before30.argb)
    f.capture.undo()
    Swag.assert(f.capture.backImg.pixelColor(0, 0).argb == before00.argb)

    f.main.sendCommandEvent(ActionImage.FlipImage)
    Swag.assert(f.capture.backImg.pixelColor(0, 0).argb == before02.argb)
    f.capture.undo()
    Swag.assert(f.capture.backImg.pixelColor(0, 0).argb == before00.argb)
}

// Rotation and explicit resize update both the image and the capture dimensions
// through serial undo groups.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    f.capture.width   = 30
    f.capture.height  = 20
    f.capture.backImg = Gui.Testing.indexedImage(30, 20)

    f.main.sendCommandEvent(ActionImage.RotateImageRight)
    Swag.assert(f.capture.backImg.width == 20)
    Swag.assert(f.capture.backImg.height == 30)
    Swag.assert(f.capture.width == 20)
    Swag.assert(f.capture.height == 30)
    Swag.assert(f.capture.canUndo())

    f.capture.undo()
    Swag.assert(f.capture.backImg.width == 30)
    Swag.assert(f.capture.backImg.height == 20)
    Swag.assert(f.capture.width == 30)
    Swag.assert(f.capture.height == 20)

    f.main.sendCommandEvent(ActionImage.RotateImageLeft)
    Swag.assert(f.capture.backImg.width == 20)
    Swag.assert(f.capture.backImg.height == 30)
    Swag.assert(f.capture.width == 20)
    Swag.assert(f.capture.height == 30)
    Swag.assert(f.capture.canUndo())

    f.capture.undo()
    Swag.assert(f.capture.backImg.width == 30)
    Swag.assert(f.capture.backImg.height == 20)
    Swag.assert(f.capture.width == 30)
    Swag.assert(f.capture.height == 20)

    g_KeepRatio = false
    f.gui.clickModalButtonWhenShown(Dialog.BtnOk)
    f.gui.withModalEdit("Width", "40")
    f.gui.withModalEdit("Height", "28")

    f.main.sendCommandEvent(ActionImage.ResizeImage)
    f.gui.pump()

    Swag.assert(f.gui.autoHandled)
    Swag.assert(f.capture.backImg.width == 40)
    Swag.assert(f.capture.backImg.height == 28)
    Swag.assert(f.capture.width == 40)
    Swag.assert(f.capture.height == 28)

    f.capture.undo()
    Swag.assert(f.capture.backImg.width == 30)
    Swag.assert(f.capture.backImg.height == 20)
    Swag.assert(f.capture.width == 30)
    Swag.assert(f.capture.height == 20)
}

// Dialog-backed image actions can now run through a real headless modal surface.
// The frame callback supplies the dialog result deterministically; no OS dialog or
// filesystem interaction is involved.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    f.capture.width   = 30
    f.capture.height  = 20
    f.capture.backImg = Gui.Testing.indexedImage(30, 20)

    g_ResizeMode = 1
    var modalFrames: u32
    var didClick:    bool
    f.gui.app.sigFrame += func|host = &f.gui, frames = &modalFrames, didClick = &didClick|(app)
    {
        frames[] += 1
        g_Width  = 42
        g_Height = 27
        if !didClick[]
        {
            Swag.assert(host.clickModalButton(Dialog.BtnOk))
            didClick[] = true
        }
    }

    f.main.sendCommandEvent(ActionImage.ExpandCapture)
    f.gui.pump()

    Swag.assert(f.gui.openedSurfaceCount() == 0)
    Swag.assert(modalFrames == 1)
    Swag.assert(didClick)
    Swag.assert(f.capture.width == 42)
    Swag.assert(f.capture.height == 27)
    Swag.assert(f.capture.backImagePos.x == 0)
    Swag.assert(f.capture.backImagePos.y == 0)
    Swag.assert(f.capture.canUndo())

    f.capture.undo()
    Swag.assert(f.capture.width == 30)
    Swag.assert(f.capture.height == 20)
}

// Expand Image uses the same modal resize dialog but only grows the backing
// bitmap; the capture canvas dimensions stay unchanged.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    f.capture.width   = 30
    f.capture.height  = 20
    f.capture.backImg = Gui.Testing.indexedImage(30, 20)

    g_ResizeMode = 1
    var didClick: bool
    f.gui.app.sigFrame += func|host = &f.gui, didClick = &didClick|(app)
    {
        g_Width  = 42
        g_Height = 27
        if !didClick[]
        {
            Swag.assert(host.clickModalButton(Dialog.BtnOk))
            didClick[] = true
        }
    }

    f.main.sendCommandEvent(ActionImage.ExpandImage)
    f.gui.pump()

    Swag.assert(didClick)
    Swag.assert(f.capture.backImg.width == 42)
    Swag.assert(f.capture.backImg.height == 27)
    Swag.assert(f.capture.width == 30)
    Swag.assert(f.capture.height == 20)
    Swag.assert(f.capture.canUndo())

    f.capture.undo()
    Swag.assert(f.capture.backImg.width == 30)
    Swag.assert(f.capture.backImg.height == 20)
    Swag.assert(f.capture.width == 30)
    Swag.assert(f.capture.height == 20)
}

// Trim Capture can be exercised entirely in memory: it crops to visible content,
// removes out-of-canvas forms, crops the backing image and can be undone.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    f.capture.width   = 100
    f.capture.height  = 80
    f.capture.backImg = Image.create(100, 80, .BGRA8)
    f.capture.backImg.fill(Argb.Zero)

    let inside = testAddShape(f.capture, 10, 15, 30, 25)
    discard testAddShape(f.capture, 150, 150, 20, 20)

    f.main.sendCommandEvent(ActionImage.TrimCapture)
    Swag.assert(f.capture.forms.count == 1)
    Swag.assert(f.capture.forms[0].buffer == inside)
    Swag.assert(f.capture.width == 30)
    Swag.assert(f.capture.height == 25)
    Gui.Testing.assertRect(inside.IForm.boundRect(), 0, 0, 30, 25)
    Swag.assert(f.capture.backImg.width == 30)
    Swag.assert(f.capture.backImg.height == 25)

    f.capture.undo()
    Swag.assert(f.capture.forms.count == 2)
    Swag.assert(f.capture.width == 100)
    Swag.assert(f.capture.height == 80)
    Gui.Testing.assertRect(inside.IForm.boundRect(), 10, 15, 30, 25)
    Swag.assert(f.capture.backImg.width == 100)
    Swag.assert(f.capture.backImg.height == 80)
}
