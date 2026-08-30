//! Format: Truevision TGA encoder component.
//! Supported: Raw or RLE true-color 24- and 32-bit output from 8-bit RGB/BGR images.
//! Not supported: Mapped, grayscale, color-corrected, and non-true-color output.
//! Role: This file owns TGA header emission, packet writing, and top-level encoding.
//
#global namespace Tga

using Core, Core.Errors

// Encodes true-color TGA images with optional run-length encoding.
internal struct Encoder {}

// Configures TGA packet encoding.
public struct EncodeOptions
{
    public rle = false     // Use TGA run-length encoded packets when true.
}

func writeTgaPixel(result: *ConcatBuffer, src: const [*] u8, pixelFormat: PixelFormat)
{
    switch pixelFormat
    {
    case .BGR8:
        result.addBytes(Swag.makeSlice(src, 3))

    case .BGRA8:
        result.addBytes(Swag.makeSlice(src, 4))

    case .RGB8:
        result.addNative(src[2])
        result.addNative(src[1])
        result.addNative(src[0])

    case .RGBA8:
        result.addNative(src[2])
        result.addNative(src[1])
        result.addNative(src[0])
        result.addNative(src[3])
    }
}

func sameTgaPixel(left, right: const [*] u8, bytesPerPixel: u64)->bool
{
    for i in bytesPerPixel
    {
        if left[i] != right[i] do
            return false
    }

    return true
}

func tgaRunLength(src: const [*] u8, index, pixelCount, bytesPerPixel: u64)->u64
{
    var result: retval = 1
    let first          = src + index * bytesPerPixel
    let limit          = Math.min(128'u64, pixelCount - index)
    if limit == 1 or !sameTgaPixel(first, first + bytesPerPixel, bytesPerPixel) do
        return result

    result = 2
    let remaining = limit - result
    if bytesPerPixel == 4
    {
        result += PackedPixel.countSame32(first, first + result * 4, remaining)
        return result
    }

    while result < limit
    {
        if !sameTgaPixel(first, first + result * bytesPerPixel, bytesPerPixel) do
            break
        result += 1
    }

    return result
}

func writeTgaRle(result: *ConcatBuffer, image: Image)
{
    let src                 = cast(const [*] u8) image.pixels.buffer!
    let bytesPerPixel       = cast(u64) image.bytesPerPixel
    let pixelCount          = cast(u64) image.width * cast(u64) image.height
    var converted: [512] u8 = undefined

    var index: u64
    while index < pixelCount
    {
        let runLength = tgaRunLength(src, index, pixelCount, bytesPerPixel)
        if runLength >= 2
        {
            result.addNative(cast(u8) (0x80 | (runLength - 1)))
            writeTgaPixel(result, src + index * bytesPerPixel, image.pixelFormat)
            index += runLength
            continue
        }

        let rawStart = index
        index += 1
        while index < pixelCount and index - rawStart < 128
        {
            if tgaRunLength(src, index, pixelCount, bytesPerPixel) >= 2 do
                break
            index += 1
        }

        let rawCount = index - rawStart
        result.addNative(cast(u8) (rawCount - 1))
        let rawSource = src + rawStart * bytesPerPixel
        switch image.pixelFormat
        {
        case .BGR8, .BGRA8:
            result.addBytes(Swag.makeSlice(rawSource, rawCount * bytesPerPixel))

        case .RGB8:
            PackedPixel.swapRedBlue24Row(rawSource, converted.buffer, rawCount)
            result.addBytes(Swag.makeSlice(converted.buffer, rawCount * bytesPerPixel))

        case .RGBA8:
            PackedPixel.swapRedBlue32Row(rawSource, converted.buffer, rawCount)
            result.addBytes(Swag.makeSlice(converted.buffer, rawCount * bytesPerPixel))
        }
    }
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"TGA - Truevision Targa", ".tga"}

    mtd impl encode(result: *ConcatBuffer, image: Image, options: #null any) fail
    {
        var userOptions: EncodeOptions
        if options.buffer != null
        {
            Debug.assert(Swag.kindOf(options) == EncodeOptions)
            userOptions = options.buffer![as EncodeOptions]
        }

        if image.width <= 0 or image.height <= 0 or !image.pixels.buffer do
            fail InvalidFormatError{"invalid image"}
        if image.width > Swag.U16.Max do
            fail UnsupportedFormatError{"width is too big"}
        if image.height > Swag.U16.Max do
            fail UnsupportedFormatError{"height is too big"}

        var header: Header
        header.imageTypeCode  = cast(u8) (userOptions.rle ? TYPE_RLE_RGB : TYPE_RGB)
        header.width          = cast(u16) image.width
        header.height         = cast(u16) image.height
        header.bitsPerPixel   = image.bitsPerPixel
        header.descriptorByte = image.pixelFormat.hasAlpha() ? 8'u8 : 0'u8
        result.addStruct(header)

        if userOptions.rle
        {
            writeTgaRle(result, image)
            return
        }

        let src           = cast(const [*] u8) image.pixels.buffer!
        let bytesPerPixel = cast(u64) image.bytesPerPixel
        let pixelCount    = cast(u64) image.width * cast(u64) image.height

        if image.pixelFormat == .BGR8 or image.pixelFormat == .BGRA8
        {
            result.addBytes(image.pixels.toSlice())
            return
        }

        var converted: Array'u8
        converted.resize(pixelCount * bytesPerPixel)
        if image.pixelFormat == .RGB8 do
            PackedPixel.swapRedBlue24Row(src, converted.buffer!, pixelCount)
        else do
            PackedPixel.swapRedBlue32Row(src, converted.buffer!, pixelCount)
        result.addBytes(converted.toSlice())
    }
}
