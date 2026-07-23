#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// The fake clipboard (enabled by the headless host) mirrors the OS semantics: a string
// or a typed payload replaces only its own format, adding an image empties everything.
#test
{
    Clipboard.setFake(true)
    defer Clipboard.setFake(false)

    @assert(!Clipboard.hasString())
    @assert(!Clipboard.hasImage())

    Clipboard.addString("hello")
    @assert(Clipboard.hasString())
    @assert(Clipboard.getString() == "hello")

    var img = Image.create(3, 2, .BGRA8)
    img.clear()
    Clipboard.addImage(img)
    @assert(Clipboard.hasImage())
    @assert(!Clipboard.hasString())
    let back = Clipboard.getImage()
    @assert(back.isValid())
    @assert(back.width == 3 and back.height == 2)

    var v = 42's32
    Clipboard.addTypedValue(&v, s32)
    var got: s32
    @assert(Clipboard.hasTypedValue(s32))
    @assert(Clipboard.getTypedValue(&got, s32))
    @assert(got == 42)
    @assert(Clipboard.hasImage())

    // Replacing the payload of an already-present format
    v = 1664
    Clipboard.addTypedValue(&v, s32)
    @assert(Clipboard.getTypedValue(&got, s32))
    @assert(got == 1664)
}
