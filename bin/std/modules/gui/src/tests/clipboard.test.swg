#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// The fake clipboard (armed by the sandbox) mirrors the OS semantics: a string or a typed
// payload replaces only its own format, adding an image empties everything.
#test
{
    Swag.assert(Clipboard.isFake())
    expect Clipboard.resetFake()

    Swag.assert(!Clipboard.hasString())
    Swag.assert(!Clipboard.hasImage())

    Clipboard.addString("hello")
    Swag.assert(Clipboard.hasString())
    Swag.assert(Clipboard.getString() == "hello")

    var img = Image.create(3, 2, .BGRA8)
    img.clear()
    Clipboard.addImage(img)
    Swag.assert(Clipboard.hasImage())
    Swag.assert(!Clipboard.hasString())
    let back = Clipboard.getImage()
    Swag.assert(back.isValid())
    Swag.assert(back.width == 3 and back.height == 2)

    var v = 42's32
    Clipboard.addTypedValue(&v, s32)
    var got: s32
    Swag.assert(Clipboard.hasTypedValue(s32))
    Swag.assert(Clipboard.getTypedValue(&got, s32))
    Swag.assert(got == 42)
    Swag.assert(Clipboard.hasImage())

    // Replacing the payload of an already-present format
    v = 1664
    Clipboard.addTypedValue(&v, s32)
    Swag.assert(Clipboard.getTypedValue(&got, s32))
    Swag.assert(got == 1664)

    Clipboard.clear()
    Swag.assert(!Clipboard.hasString())
    Swag.assert(!Clipboard.hasImage())
    Swag.assert(!Clipboard.hasTypedValue(s32))
}
