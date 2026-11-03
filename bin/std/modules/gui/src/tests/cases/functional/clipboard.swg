#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Copying premultiplied samples preserves their logical color and owns the copied storage.
#test
{
    Swag.require(Clipboard.isFake())
    expect Clipboard.resetFake()
    defer Clipboard.clear()

    const Bytes: [4] u8 = [64, 32, 16, 128]
    var source        = Image.create(1, 1, .RGBA8, Bytes, .Premultiplied)
    let expectedColor = source.pixelColor(0, 0)
    Clipboard.addImage(source)
    source.clear()

    let copied = Clipboard.getImage()
    Swag.require(copied.isValid())
    Swag.require(copied.pixelColor(0, 0) == expectedColor)
}

// The fake clipboard (armed by the sandbox) mirrors the OS semantics: a string or a typed
// payload replaces only its own format, adding an image empties everything.
#test
{
    Swag.require(Clipboard.isFake())
    expect Clipboard.resetFake()

    Swag.require(not Clipboard.hasString())
    Swag.require(not Clipboard.hasImage())

    Clipboard.addString("hello")
    Swag.require(Clipboard.hasString())
    Swag.require(Clipboard.getString() == "hello")

    var img = Image.create(3, 2, .BGRA8)
    img.clear()
    Clipboard.addImage(img)
    Swag.require(Clipboard.hasImage())
    Swag.require(not Clipboard.hasString())
    let back = Clipboard.getImage()
    Swag.require(back.isValid())
    Swag.require(back.width == 3 and back.height == 2)

    var v = 42's32
    Clipboard.addTypedValue(&v, s32)
    var got: s32
    Swag.require(Clipboard.hasTypedValue(s32))
    var found = Clipboard.getTypedValue(&got, s32)
    Swag.require(found)
    Swag.require(got == 42)
    Swag.require(Clipboard.hasImage())

    // Adding a value of a format already present replaces its payload.
    v = 1664
    Clipboard.addTypedValue(&v, s32)
    found = Clipboard.getTypedValue(&got, s32)
    Swag.require(found)
    Swag.require(got == 1664)

    Clipboard.clear()
    Swag.require(not Clipboard.hasString())
    Swag.require(not Clipboard.hasImage())
    Swag.require(not Clipboard.hasTypedValue(s32))
}

// A standalone text copy replaces rich payloads, while adding text preserves them.
#test
{
    Swag.require(Clipboard.isFake())
    expect Clipboard.resetFake()
    defer Clipboard.clear()

    var img = Image.create(3, 2, .BGRA8)
    img.clear()
    Clipboard.addImage(img)
    var value = 42's32
    Clipboard.addTypedValue(&value, s32)
    Clipboard.addString("old text")
    Swag.require(Clipboard.hasImage() and Clipboard.hasTypedValue(s32))

    Clipboard.setString("C:\\données\\été.txt")
    Swag.require(Clipboard.hasString())
    Swag.require(Clipboard.getString() == "C:\\données\\été.txt")
    Swag.require(not Clipboard.hasImage() and not Clipboard.hasTypedValue(s32))

    Clipboard.setString("été.txt")
    Swag.require(Clipboard.getString() == "été.txt")

    Clipboard.setString("")
    Swag.require(Clipboard.hasString() and Clipboard.getString().isEmpty())
}
