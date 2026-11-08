#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors, Pixel

// Both packed channel orders produce the same top-down BT.709 picture and shared chroma block.
#test
{
    // Image storage starts with the bottom row: red, blue, then black, white above it.
    const Rgb: [12] u8 = [255, 0, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255]
    let image = Image.create(2, 2, .RGB8, Swag.makeSlice(&Rgb[0], Rgb.count))
    var frame: Nv12Frame
    expect frame.convertFrom(&image)
    const Expected: [6] u8 = [16, 235, 63, 32, 150, 153]
    Swag.require(frame.width == 2 and frame.height == 2)
    Swag.require(frame.luma().count == 4 and frame.chroma().count == 2)
    Swag.require(Memory.compare(frame.bytes.storage(), &Expected[0], Expected.count) == 0)

    const Bgra: [16] u8 = [0, 0, 255, 0, 255, 0, 0, 128,
                           0, 0, 0, 255, 255, 255, 255, 16]
    let reordered = Image.create(2, 2, .BGRA8, Swag.makeSlice(&Bgra[0], Bgra.count))
    expect frame.convertFrom(&reordered)
    Swag.require(Memory.compare(frame.bytes.storage(), &Expected[0], Expected.count) == 0)

    const Bgr: [12] u8 = [0, 0, 255, 255, 0, 0, 0, 0, 0, 255, 255, 255]
    let bgrImage = Image.create(2, 2, .BGR8, Swag.makeSlice(&Bgr[0], Bgr.count))
    expect frame.convertFrom(&bgrImage)
    Swag.require(Memory.compare(frame.bytes.storage(), &Expected[0], Expected.count) == 0)

    const Rgba: [16] u8 = [255, 0, 0, 0, 0, 0, 255, 128,
                           0, 0, 0, 255, 255, 255, 255, 16]
    let rgbaImage = Image.create(2, 2, .RGBA8, Swag.makeSlice(&Rgba[0], Rgba.count))
    expect frame.convertFrom(&rgbaImage)
    Swag.require(Memory.compare(frame.bytes.storage(), &Expected[0], Expected.count) == 0)

    const Wide: [24] u8 = [0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 255, 255,
                           0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 255, 255]
    let wideImage = Image.create(4, 2, .RGB8, Swag.makeSlice(&Wide[0], Wide.count))
    expect frame.convertFrom(&wideImage)
    const WideExpected: [12] u8 = [16, 16, 235, 235, 16, 16, 235, 235, 128, 128, 128, 128]
    Swag.require(frame.width == 4 and frame.luma().count == 8 and frame.chroma().count == 4)
    Swag.require(Memory.compare(frame.bytes.storage(), &WideExpected[0], WideExpected.count) == 0)
}

// Unsupported formats and odd dimensions leave a previously converted frame intact.
#test
{
    const Black: [12] u8 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    let image = Image.create(2, 2, .RGB8, Swag.makeSlice(&Black[0], Black.count))
    var frame: Nv12Frame
    expect frame.convertFrom(&image)
    const Expected: [6] u8 = [16, 16, 16, 16, 128, 128]
    Swag.require(Memory.compare(frame.bytes.storage(), &Expected[0], Expected.count) == 0)
    var rejected: Swag.Error
    let odd = Image.create(3, 2, .RGB8)
    discard catch frame.convertFrom(&odd) as rejected
    Swag.require(rejected.value() is BadParameterError)
    let gray = Image.create(2, 2, .Gray8)
    discard catch frame.convertFrom(&gray) as rejected
    Swag.require(rejected.value() is UnsupportedFormatError)
    Swag.require(frame.width == 2 and frame.height == 2)
    Swag.require(Memory.compare(frame.bytes.storage(), &Expected[0], Expected.count) == 0)
}
