#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Copying a virtual-desktop frame preserves every pixel.
#[Swag.TestTag("stress")]
#test
{
    const Width  = 7680'u64
    const Height = 2168'u64
    var source = Image.create(cast(s32, Width), cast(s32, Height), .BGRA8)
    var output = Image.create(cast(s32, Width), cast(s32, Height), .BGRA8)
    let pixels = cast([*] u32, source.pixels.storage())
    for index in Width * Height do
        pixels[index] = cast(u32, (index * 2_654_435_761'u64) & 0xFFFF_FFFF)

    copyFrameBytes(output.pixels.storage(), source.pixels.storage(), source.byteCount)
    Swag.require(Slice.equals(output.pixels.toSlice(), source.pixels.toSlice()))
}
