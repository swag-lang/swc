#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Parallel BGRA8 bands must match the scalar BGR8 path across a full 4K picture.
#[Swag.TestTag("stress")]
#test
{
    const Width  = 3840
    const Height = 2160
    let bgr  = Image.create(Width, Height, .BGR8)
    let bgra = Image.create(Width, Height, .BGRA8)
    let bgrPixels  = bgr.pixels.storage()
    let bgraPixels = bgra.pixels.storage()
    for y in Height
    {
        for x in Width
        {
            let pixel = cast(u64, y) * Width + cast(u64, x)
            let blue  = cast(u8, (x * 37 + y * 19 + 11) & 0xFF)
            let green = cast(u8, (x * 53 + y * 29 + 97) & 0xFF)
            let red   = cast(u8, (x * 71 + y * 43 + 193) & 0xFF)
            let bgrOffset  = pixel * 3
            let bgraOffset = pixel * 4
            bgrPixels[bgrOffset]       = blue
            bgrPixels[bgrOffset + 1]   = green
            bgrPixels[bgrOffset + 2]   = red
            bgraPixels[bgraOffset]     = blue
            bgraPixels[bgraOffset + 1] = green
            bgraPixels[bgraOffset + 2] = red
            bgraPixels[bgraOffset + 3] = cast(u8, (x * 83 + y * 59) & 0xFF)
        }
    }

    var bgrFrame:  Nv12Frame
    var bgraFrame: Nv12Frame
    expect bgrFrame.convertFrom(&bgr)
    expect bgraFrame.convertFrom(&bgra)
    Swag.require(bgrFrame.bytes.count == cast(u64, Width) * Height * 3 / 2)
    Swag.require(bgraFrame.bytes.count == bgrFrame.bytes.count)
    for byte in bgrFrame.bytes.count do
        Swag.require(bgraFrame.bytes[byte] == bgrFrame.bytes[byte])
}
