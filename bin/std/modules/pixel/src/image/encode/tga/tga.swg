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

#[Swag.Inline]
private func writeTgaPixel(target: [*] u8, src: const [*] u8, pixelFormat: PixelFormat)
{
    switch pixelFormat
    {
    case .BGR8:
        cast(*u16, target)[] = cast(const *u16, src)[]
        target[2] = src[2]

    case .BGRA8:
        cast(*u32, target)[] = cast(const *u32, src)[]

    case .RGB8:
        target[0] = src[2]
        target[1] = src[1]
        target[2] = src[0]

    case .RGBA8:
        target[0] = src[2]
        target[1] = src[1]
        target[2] = src[0]
        target[3] = src[3]

    default:
        unreachable
    }
}

#[Swag.Inline]
func sameTgaPixel(left, right: const [*] u8, bytesPerPixel: u64)->bool
{
    for i in bytesPerPixel
    {
        if left[i] != right[i]
        {
            return false
        }
    }

    return true
}

func tgaRunLength(src: const [*] u8, index, rowEnd, bytesPerPixel: u64)->u64
{
    var result: #returntype = 1
    let first = src + index * bytesPerPixel
    let limit = Math.min(128_u64, pixelCount - index)
    if limit == 1 or not sameTgaPixel(first, first + bytesPerPixel, bytesPerPixel)
    {
        return result
    }

    result = 2
    let remaining = limit - result
    if bytesPerPixel == 4
    {
        result += PackedPixel.countSame32(first, first + result * 4, remaining)
        return result
    }

    // Short repeats use scalar comparisons; longer ones pay for the vector pattern once.
    while result < limit and result < 6
    {
        if not sameTgaPixel(first, first + result * bytesPerPixel, bytesPerPixel)
        {
            break
        }

        result += 1
    }

    if result < limit do
        result += PackedPixel.countSame24(first, first + result * 3, limit - result)
    return result
}

private func nextTgaRawEnd(source: const [*] u8, first, packetEnd, rowEnd, bytesPerPixel: u64)->u64
{
    using Math.Simd

    let end = Math.min(packetEnd, rowEnd - 1)
    if first >= end do
        return packetEnd

    var x = first
    if bytesPerPixel == 4
    {
        let pixels = cast(const [*] u32, source)
        while end - x >= 4
        {
            let matches = bitmask(load(pixels + x) == load(pixels + x + 1))
            if matches do
                return x + Math.trailingZeros(matches)
            x += 4
        }
    }
    else
    {
        // Matching triplets leave bits 0, 3, 6, or 9 set after combining the byte masks.
        while end - x >= 6
        {
            let at      = source + x * 3
            let matches = bitmask(load(at) == load(at + 3))
            let pairs   = matches & (matches >> 1) & (matches >> 2) & 0x249
            if pairs do
                return x + Math.trailingZeros(pairs) / 3
            x += 4
        }
    }

    for i in x until end
    {
        let pixel = source + i * bytesPerPixel
        if sameTgaPixel(pixel, pixel + bytesPerPixel, bytesPerPixel) do
            return i
    }

    return packetEnd
}

func writeTgaRle(result: *ConcatBuffer, image: Image)
{
    let src = cast(const [*] u8, image.pixels.storage())
    let bytesPerPixel = cast(u64, image.bytesPerPixel)
    const BucketBytes = 32 * 1024
    result.setBucketSize(Math.min(image.byteCount + 128, cast(u64, BucketBytes)))

    let width = cast(u64, image.width)
    var index: u64

    // Each packet stays within a scanline as required by TGA 2.0 readers.
    for y in image.height
    {
        let rowEnd = (y + 1) * width
        while index < rowEnd
        {
            let runLength = tgaRunLength(src, index, rowEnd, bytesPerPixel)
            if runLength >= 2
            {
                let packet = result.reserveInPlace(1 + bytesPerPixel)
                packet[0] = cast(u8, (0x80 | (runLength - 1)))
                writeTgaPixel(packet + 1, src + index * bytesPerPixel, image.pixelFormat)
                index += runLength
                continue
            }

        let rawStart = index
        index += 1
        while index < pixelCount and index - rawStart < 128
        {
            if tgaRunLength(src, index, pixelCount, bytesPerPixel) >= 2
            {
                break
            }

            index += 1
        }

            let rawCount  = index - rawStart
            let rawSize   = rawCount * bytesPerPixel
            let rawSource = src + rawStart * bytesPerPixel
            let packet    = result.reserveInPlace(1 + rawSize)
            packet[0] = cast(u8, (rawCount - 1))
            let target = packet + 1
            switch image.pixelFormat
            {
            case .BGR8, .BGRA8: Memory.copy(target, rawSource, rawSize)
            case .RGB8:         PackedPixel.swapRedBlue24Row(rawSource, target, rawCount)
            case .RGBA8:        PackedPixel.swapRedBlue32Row(rawSource, target, rawCount)
            default:            unreachable
            }
        }
    }
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"TGA - Truevision Targa", ".tga"}

    mtd impl encode(result: *ConcatBuffer, image: Image, options: any?) fail
    {
        var userOptions: EncodeOptions
        if options.buffer != null
        {
            if Swag.kindOf(options) != EncodeOptions
            {
                fail BadParameterError{"TGA encoder options must be Tga.EncodeOptions"}
            }

            userOptions = cast(const *EncodeOptions, unwrap options.buffer)[]
        }

        if image.width <= 0 or image.height <= 0 or not image.pixels.buffer
        {
            fail InvalidFormatError{"invalid image"}
        }

        if image.pixelFormat != .BGR8 and
           image.pixelFormat != .BGRA8 and
           image.pixelFormat != .RGB8 and
           image.pixelFormat != .RGBA8
        {
            fail UnsupportedFormatError{"TGA encoding accepts only 8-bit RGB and BGR pixels"}
        }

        if image.width > Swag.U16.Max
        {
            fail UnsupportedFormatError{"width is too big"}
        }

        if image.height > Swag.U16.Max
        {
            fail UnsupportedFormatError{"height is too big"}
        }

        with var header: Header
        {
            .imageTypeCode  = cast(u8, (userOptions.rle ? TYPE_RLE_RGB : TYPE_RGB))
            .width          = cast(u16, image.width)
            .height         = cast(u16, image.height)
            .bitsPerPixel   = image.bitsPerPixel
            .descriptorByte = image.pixelFormat.hasAlpha() ? 8_u8 : 0_u8
        }

        if not userOptions.rle do
            result.grow(#sizeof(Header) + image.byteCount)
        result.addStruct(header)

        if userOptions.rle
        {
            writeTgaRle(result, image)
            return
        }

        let src           = cast(const [*] u8, image.pixels.storage())
        let bytesPerPixel = cast(u64, image.bytesPerPixel)
        let pixelCount    = cast(u64, image.width) * cast(u64, image.height)

        if image.pixelFormat == .BGR8 or image.pixelFormat == .BGRA8
        {
            result.addBytes(image.pixels.toSlice())
            return
        }

        var converted: Array!{u8}
        converted.resize(pixelCount * bytesPerPixel)
        if image.pixelFormat == .RGB8
        {
            PackedPixel.swapRedBlue24Row(src, converted.storage(), pixelCount)
        }
        else
        {
            PackedPixel.swapRedBlue32Row(src, converted.storage(), pixelCount)
        }

        result.addBytes(converted.toSlice())
    }
}
