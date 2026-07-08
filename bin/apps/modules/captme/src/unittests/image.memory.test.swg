#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Image actions that do not open dialogs mutate the backing image in memory and
// remain undoable through the normal action path.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    f.capture.width = 4
    f.capture.height = 3
    f.capture.backImg = captmeTestIndexedImage(4, 3)

    let before00 = f.capture.backImg.getPixelColor(0, 0)
    let before30 = f.capture.backImg.getPixelColor(3, 0)
    let before02 = f.capture.backImg.getPixelColor(0, 2)

    @assert(captmeTestActionExecute'ActionImage(f.main, ActionImage.MirrorImage))
    @assert(f.capture.backImg.getPixelColor(0, 0).argb == before30.argb)
    f.capture.undo()
    @assert(f.capture.backImg.getPixelColor(0, 0).argb == before00.argb)

    @assert(captmeTestActionExecute'ActionImage(f.main, ActionImage.FlipImage))
    @assert(f.capture.backImg.getPixelColor(0, 0).argb == before02.argb)
    f.capture.undo()
    @assert(f.capture.backImg.getPixelColor(0, 0).argb == before00.argb)

    f.shutdown()
}

// Rotation and explicit resize update both the image and the capture dimensions
// through serial undo groups.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    f.capture.width = 30
    f.capture.height = 20
    f.capture.backImg = captmeTestIndexedImage(30, 20)

    @assert(captmeTestActionExecute'ActionImage(f.main, ActionImage.RotateImageRight))
    @assert(f.capture.backImg.width == 20)
    @assert(f.capture.backImg.height == 30)
    @assert(f.capture.width == 20)
    @assert(f.capture.height == 30)
    @assert(f.capture.canUndo())

    f.capture.undo()
    @assert(f.capture.backImg.width == 30)
    @assert(f.capture.backImg.height == 20)
    @assert(f.capture.width == 30)
    @assert(f.capture.height == 20)

    f.main.doProcessImage(ActionImage.ResizeImage, w: 40, h: 28)
    @assert(f.capture.backImg.width == 40)
    @assert(f.capture.backImg.height == 28)
    @assert(f.capture.width == 40)
    @assert(f.capture.height == 28)

    f.capture.undo()
    @assert(f.capture.backImg.width == 30)
    @assert(f.capture.backImg.height == 20)
    @assert(f.capture.width == 30)
    @assert(f.capture.height == 20)

    f.shutdown()
}

// Dialog-backed image actions can now run through a real headless modal surface.
// The frame callback supplies the dialog result deterministically; no OS dialog or
// filesystem interaction is involved.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    f.capture.width = 30
    f.capture.height = 20
    f.capture.backImg = captmeTestIndexedImage(30, 20)

    g_ResizeMode = 1
    var modalFrames: u32
    var didClick: bool
    f.gui.app.sigFrame += func|host = &f.gui, frames = &modalFrames, didClick = &didClick|(app)
    {
        dref frames += 1
        g_Width = 42
        g_Height = 27
        if !dref didClick
        {
            @assert(host.clickModalButton(Dialog.BtnOk))
            dref didClick = true
        }
    }

    @assert(captmeTestActionExecute'ActionImage(f.main, ActionImage.ExpandCapture))
    f.gui.pump()

    @assert(f.gui.app.surfaces.count == 0)
    @assert(modalFrames == 1)
    @assert(didClick)
    @assert(f.capture.width == 42)
    @assert(f.capture.height == 27)
    @assert(f.capture.backImagePos.x == 0)
    @assert(f.capture.backImagePos.y == 0)
    @assert(f.capture.canUndo())

    f.capture.undo()
    @assert(f.capture.width == 30)
    @assert(f.capture.height == 20)

    f.shutdown()
}

// Trim Capture can be exercised entirely in memory: it crops to visible content,
// removes out-of-canvas forms, crops the backing image and can be undone.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    f.capture.width = 100
    f.capture.height = 80
    f.capture.backImg = Image.create(100, 80, .BGRA8)
    f.capture.backImg.fill(Argb.Zero)

    let inside = captmeTestAddShape(f.capture, 10, 15, 30, 25)
    discard captmeTestAddShape(f.capture, 150, 150, 20, 20)

    @assert(captmeTestActionExecute'ActionImage(f.main, ActionImage.TrimCapture))
    @assert(f.capture.forms.count == 1)
    @assert(@dataof(f.capture.forms[0]) == inside)
    @assert(f.capture.width == 30)
    @assert(f.capture.height == 25)
    captmeTestAssertRect(inside.IForm.boundRect(), 0, 0, 30, 25)
    @assert(f.capture.backImg.width == 30)
    @assert(f.capture.backImg.height == 25)

    f.capture.undo()
    @assert(f.capture.forms.count == 2)
    @assert(f.capture.width == 100)
    @assert(f.capture.height == 80)
    captmeTestAssertRect(inside.IForm.boundRect(), 10, 15, 30, 25)
    @assert(f.capture.backImg.width == 100)
    @assert(f.capture.backImg.height == 80)

    f.shutdown()
}
