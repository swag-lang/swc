#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors, Pixel

// Row order and chroma placement stay correct beyond a single two-by-two block.
#test
{
    // Bottom two rows are blue; top two rows are red. Alpha must not affect NV12.
    const Bgra: [32] u8 = [255, 0, 0, 0, 255, 0, 0, 255,
                            255, 0, 0, 128, 255, 0, 0, 1,
                            0, 0, 255, 0, 0, 0, 255, 255,
                            0, 0, 255, 128, 0, 0, 255, 1]
    let image = Image.create(2, 4, .BGRA8, Swag.makeSlice(&Bgra[0], Bgra.count))
    var frame: Nv12Frame
    expect frame.convertFrom(&image)
    const Expected: [12] u8 = [63, 63, 63, 63, 32, 32, 32, 32, 102, 240, 240, 118]
    Swag.require(frame.width == 2 and frame.height == 4)
    Swag.require(frame.luma().count == 8 and frame.chroma().count == 4)
    Swag.require(Memory.compare(frame.bytes.storage(), &Expected[0], Expected.count) == 0)
}

// BT.709 studio-range reference values cover the primary colors and neutral white.
#test
{
    const Rgb: [24] u8 = [0, 255, 0, 0, 255, 0, 255, 255, 255, 255, 255, 255,
                          0, 255, 0, 0, 255, 0, 255, 255, 255, 255, 255, 255]
    let image = Image.create(4, 2, .RGB8, Swag.makeSlice(&Rgb[0], Rgb.count))
    var frame: Nv12Frame
    expect frame.convertFrom(&image)
    const Expected: [12] u8 = [173, 173, 235, 235, 173, 173, 235, 235, 42, 26, 128, 128]
    Swag.require(Memory.compare(frame.bytes.storage(), &Expected[0], Expected.count) == 0)

    // The same colors with opaque and transparent alpha produce identical samples.
    const Rgba: [32] u8 = [0, 255, 0, 0, 0, 255, 0, 255, 255, 255, 255, 0, 255, 255, 255, 255,
                           0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255, 255, 0]
    let rgba = Image.create(4, 2, .RGBA8, Swag.makeSlice(&Rgba[0], Rgba.count))
    expect frame.convertFrom(&rgba)
    Swag.require(Memory.compare(frame.bytes.storage(), &Expected[0], Expected.count) == 0)

    const Bgr: [24] u8 = [0, 255, 0, 0, 255, 0, 255, 255, 255, 255, 255, 255,
                          0, 255, 0, 0, 255, 0, 255, 255, 255, 255, 255, 255]
    let bgr = Image.create(4, 2, .BGR8, Swag.makeSlice(&Bgr[0], Bgr.count))
    expect frame.convertFrom(&bgr)
    Swag.require(Memory.compare(frame.bytes.storage(), &Expected[0], Expected.count) == 0)
}

// Rejected images preserve the prior dimensions, bytes, and plane boundaries.
#test
{
    const White: [16] u8 = [255, 255, 255, 255, 255, 255, 255, 255,
                            255, 255, 255, 255, 255, 255, 255, 255]
    let image = Image.create(2, 2, .BGRA8, Swag.makeSlice(&White[0], White.count))
    var frame: Nv12Frame
    expect frame.convertFrom(&image)
    const Expected: [6] u8 = [235, 235, 235, 235, 128, 128]

    var rejected: Swag.Error
    var empty: Image
    discard catch frame.convertFrom(&empty) as rejected
    Swag.require(rejected.value() is BadParameterError)
    let oddHeight = Image.create(2, 3, .BGRA8)
    discard catch frame.convertFrom(&oddHeight) as rejected
    Swag.require(rejected.value() is BadParameterError)
    let oddWidth = Image.create(3, 2, .BGRA8)
    discard catch frame.convertFrom(&oddWidth) as rejected
    Swag.require(rejected.value() is BadParameterError)
    let gray = Image.create(2, 2, .Gray8)
    discard catch frame.convertFrom(&gray) as rejected
    Swag.require(rejected.value() is UnsupportedFormatError)
    Swag.require(frame.width == 2 and frame.height == 2)
    Swag.require(frame.luma().count == 4 and frame.chroma().count == 2)
    Swag.require(Memory.compare(frame.bytes.storage(), &Expected[0], Expected.count) == 0)
}

// The specialized BGRA8 path must match the BGR8 path for every Y and Cb/Cr sample.
#test
{
    let bgr  = Image.create(8, 6, .BGR8)
    let bgra = Image.create(8, 6, .BGRA8)
    let bgrPixels  = bgr.pixels.storage()
    let bgraPixels = bgra.pixels.storage()
    for pixel in 48'u64
    {
        let blue  = cast(u8, (pixel * 37 + 11) & 0xFF)
        let green = cast(u8, (pixel * 53 + 97) & 0xFF)
        let red   = cast(u8, (pixel * 71 + 193) & 0xFF)
        let bgrOffset  = pixel * 3
        let bgraOffset = pixel * 4
        bgrPixels[bgrOffset]      = blue
        bgrPixels[bgrOffset + 1]  = green
        bgrPixels[bgrOffset + 2]  = red
        bgraPixels[bgraOffset]     = blue
        bgraPixels[bgraOffset + 1] = green
        bgraPixels[bgraOffset + 2] = red
        bgraPixels[bgraOffset + 3] = cast(u8, (pixel * 83 + 19) & 0xFF)
    }

    var bgrFrame:  Nv12Frame
    var bgraFrame: Nv12Frame
    expect bgrFrame.convertFrom(&bgr)
    expect bgraFrame.convertFrom(&bgra)
    Swag.require(bgrFrame.bytes.count == 8 * 6 * 3 / 2)
    Swag.require(bgraFrame.bytes.count == bgrFrame.bytes.count)
    for byte in bgrFrame.bytes.count do
        Swag.require(bgraFrame.bytes[byte] == bgrFrame.bytes[byte])
}
