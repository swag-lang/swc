#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Copying premultiplied samples preserves their logical color and owns the copied storage.
#test
{
    Swag.assert(Clipboard.isFake())
    expect Clipboard.resetFake()
    defer Clipboard.clear()

    const Bytes: [4] u8 = [64, 32, 16, 128]
    var source        = Image.create(1, 1, .RGBA8, Bytes, .Premultiplied)
    let expectedColor = source.pixelColor(0, 0)
    Clipboard.addImage(source)
    source.clear()

    let copied = Clipboard.getImage()
    Swag.assert(copied.isValid())
    Swag.assert(copied.pixelColor(0, 0) == expectedColor)
}

// The fake clipboard (armed by the sandbox) mirrors the OS semantics: a string or a typed
// payload replaces only its own format, adding an image empties everything.
#test
{
    Swag.assert(Clipboard.isFake())
    expect Clipboard.resetFake()

    Swag.assert(not Clipboard.hasString())
    Swag.assert(not Clipboard.hasImage())

    Clipboard.addString("hello")
    Swag.assert(Clipboard.hasString())
    Swag.assert(Clipboard.getString() == "hello")

    var img = Image.create(3, 2, .BGRA8)
    img.clear()
    Clipboard.addImage(img)
    Swag.assert(Clipboard.hasImage())
    Swag.assert(not Clipboard.hasString())
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
    Swag.assert(not Clipboard.hasString())
    Swag.assert(not Clipboard.hasImage())
    Swag.assert(not Clipboard.hasTypedValue(s32))
}

// A standalone text copy replaces rich payloads, while adding text preserves them.
#test
{
    Swag.assert(Clipboard.isFake())
    expect Clipboard.resetFake()
    defer Clipboard.clear()

    var img = Image.create(3, 2, .BGRA8)
    img.clear()
    Clipboard.addImage(img)
    var value = 42's32
    Clipboard.addTypedValue(&value, s32)
    Clipboard.addString("old text")
    Swag.assert(Clipboard.hasImage() and Clipboard.hasTypedValue(s32))

    Clipboard.setString("C:\\données\\été.txt")
    Swag.assert(Clipboard.hasString())
    Swag.assert(Clipboard.getString() == "C:\\données\\été.txt")
    Swag.assert(not Clipboard.hasImage() and not Clipboard.hasTypedValue(s32))

    Clipboard.setString("été.txt")
    Swag.assert(Clipboard.getString() == "été.txt")

    Clipboard.setString("")
    Swag.assert(Clipboard.hasString() and Clipboard.getString().isEmpty())
}
