//! Format: Quite OK Image decoder.
//! Supported: QOI RGB and RGBA images in either declared color space.
//! Not supported: Concatenated images or bytes after the required end marker.
//! Role: This file owns QOI header validation and chunk reconstruction.
//
#global namespace Qoi

using Core, Core.Errors

const Magic: [4] u8 = ['q', 'o', 'i', 'f']
const HeaderSize    = 14_u64
const EndMarkerSize = 8_u64

// Decodes QOI images into RGB8 or RGBA8 storage.
internal struct Decoder {}

#[Swag.Inline]
func readU32BigEndian(source: const [*] u8)->u32
{
    return (cast(u32, source[0]) << 24) |
           (cast(u32, source[1]) << 16) |
           (cast(u32, source[2]) << 8) |
           cast(u32, source[3])
}

#[Swag.Inline]
func hashWord(pixel: u32)->u8
{
    // Separate the channels into 16-bit lanes so the weighted sum fits in the high lane.
    let even = (pixel & 0x00FF_00FF_u32) * #wrap 0x0003_0007_u32
    let odd  = ((pixel >> 8) & 0x00FF_00FF_u32) * #wrap 0x0005_000B_u32
    return cast(u8, (((even + #wrap odd) >> 16) & 63))
}

#[Swag.Inline]
private func addRgbDeltas(pixel: u32, red, green, blue: s32)->u32
{
    let delta = cast(u32, cast #wrap(u8, red)) |
                (cast(u32, cast #wrap(u8, green)) << 8) |
                (cast(u32, cast #wrap(u8, blue)) << 16)

    // Add each byte independently, including negative deltas reduced modulo 256.
    let low = (pixel & 0x7F7F_7F7F_u32) + (delta & 0x7F7F_7F7F_u32)
    return low ^ ((pixel ^ delta) & 0x8080_8080_u32)
}

private func(CHANNELS: u32) decodePayload(image: *Image, buffer: const [..] u8)->u64 fail
{
    let source     = buffer.buffer
    let width      = cast(u64, image.width)
    let height     = cast(u64, image.height)
    var index: [64] u32
    var previous   = 0xFF00_0000_u32
    var input      = HeaderSize
    var repeated   = 0_u64
    let chunkLimit = buffer.count - EndMarkerSize

    // Decode forward within each row while placing the rows bottom-up.
    for y in height
    {
        var target = image.pixels.storage() + cast(u64, (height - y - 1)) * image.rowStride
        var x      = 0_u64
        while x < width
        {
            if repeated
            {
                let span = Math.min(repeated, width - x)
                #static if CHANNELS == 4
                {
                    using Math.Simd
                    let pattern = splat(previous)
                    let words   = cast([*] u32, target)
                    var filled  = 0_u64
                    while span - filled >= 4
                    {
                        store(words + filled, pattern)
                        filled += 4
                    }

                    for i in filled until span
                    {
                        words[i] = previous
                    }
                }
                else
                {
                    let pixel = previous
                    PackedPixel.fillBgr24Row(cast(const [*] u8, &pixel), target, span)
                }

                target   += span * CHANNELS
                x        += span
                repeated -= span
                continue
            }

            if input >= chunkLimit
            {
                fail InvalidFormatError{"QOI data ends before every pixel is decoded"}
            }

            let tag = source[input]
            input += 1
            if tag == 0xFE
            {
                if input + 3 > chunkLimit
                {
                    fail InvalidFormatError{"QOI RGB chunk is truncated"}
                }

                // The mandatory end marker leaves room for the unused high byte.
                let word = cast(const [*] u32, source + input)[0]
                previous = (previous & 0xFF00_0000_u32) | (word & 0x00FF_FFFF_u32)
                input    += 3
            }
            else if tag == 0xFF
            {
                #static if CHANNELS == 4
                {
                    if width - x >= 4 and
                       input + 19 <= chunkLimit and
                       source[input + 4] == 0xFF and
                       source[input + 9] == 0xFF and
                       source[input + 14] == 0xFF
                    {
                        using Math.Simd

                        // Drop the three tags between the four RGBA pixels.
                        const RgbaWords = cast(U8x16, [0_u8, 1, 2, 3, 5, 6, 7, 8, 10, 11, 12, 13, 28, 29, 30, 31])
                        let first  = load(source + input)
                        let last   = load(source + input + 3)
                        let pixels = cast #bit(U32x4, permute2(first, last, RgbaWords))
                        let even   = (pixels & 0x00FF00FF_u32) * 0x00030007_u32
                        let odd    = ((pixels >> 8) & 0x00FF00FF_u32) * 0x0005000B_u32
                        let hashes = ((even + odd) >> 16) & 63_u32

                        // Preserve insertion order for pixels that share an index.
                        index[hashes[0]] = pixels[0]
                        index[hashes[1]] = pixels[1]
                        index[hashes[2]] = pixels[2]
                        index[hashes[3]] = pixels[3]
                        store(cast([*] u32, target), pixels)
                        previous = pixels[3]
                        target   += 16
                        input    += 19
                        x        += 4
                        continue
                    }
                }

                if input + 4 > chunkLimit
                {
                    fail InvalidFormatError{"QOI RGBA chunk is truncated"}
                }

                previous = cast(const [*] u32, source + input)[0]
                input    += 4
            }
            else
            {
                switch tag & 0xC0
                {
                case 0x00:
                    previous = index[tag & 63]

                case 0x40:
                    previous = addRgbDeltas(previous, cast(s32, ((tag >> 4) & 3)) - 2, cast(s32, ((tag >> 2) & 3)) - 2, cast(s32, (tag & 3)) - 2)

                case 0x80:
                    if input >= chunkLimit
                    {
                        fail InvalidFormatError{"QOI luma chunk is truncated"}
                    }

                    let next = source[input]
                    input += 1
                    let greenDelta = cast(s32, (tag & 63)) - 32
                    previous = addRgbDeltas(previous,
                                            greenDelta + cast(s32, ((next >> 4) & 15)) - 8,
                                            greenDelta,
                                            greenDelta + cast(s32, (next & 15)) - 8)

                case 0xC0:
                    repeated = cast(u64, (tag & 63)) + 1
                    let remaining = cast(u64, (height - y - 1)) * width + width - x
                    if repeated > remaining
                    {
                        fail InvalidFormatError{"QOI run exceeds the image dimensions"}
                    }

                    index[hashWord(previous)] = previous
                    continue
                }
            }

            index[hashWord(previous)] = previous
            #static if CHANNELS == 4
            {
                cast([*] u32, target)[0] = previous
            }
            else
            {
                cast([*] u16, target)[0] = cast #wrap(u16, previous)
                target[2] = cast(u8, ((previous >> 16) & 255))
            }

            target += CHANNELS
            x      += 1
        }
    }

    return input
}

internal impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"QOI - Quite OK Image", ".qoi"}

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        if buffer.count < HeaderSize + EndMarkerSize
        {
            fail InvalidFormatError{"QOI data is shorter than its header and end marker"}
        }

        let source = buffer.buffer
        for i in 4 where source[i] != Magic[i]
        {
            fail InvalidFormatError{"QOI signature is invalid"}
        }

        let width      = readU32BigEndian(source + 4)
        let height     = readU32BigEndian(source + 8)
        let channels   = source[12]
        let colorSpace = source[13]
        if width == 0 or height == 0
        {
            fail InvalidFormatError{"QOI dimensions must be positive"}
        }

        if width > cast(u32, Swag.S32.Max) or height > cast(u32, Swag.S32.Max)
        {
            fail UnsupportedFormatError{"QOI dimensions exceed the image limits"}
        }

        if channels != 3 and channels != 4
        {
            fail InvalidFormatError{"QOI channel count must be 3 or 4"}
        }

        if colorSpace > 1
        {
            fail InvalidFormatError{"QOI color-space value must be 0 or 1"}
        }

        if cast(u64, width) * cast(u64, height) > Swag.U64.Max / channels
        {
            fail UnsupportedFormatError{"QOI image is too large"}
        }

        let pixelFormat: PixelFormat = channels == 4 ? .RGBA8 : .RGB8
        if width > cast(u32, Swag.S32.Max) / channels
        {
            fail UnsupportedFormatError{"QOI image row exceeds the image limits"}
        }

        try options.checkImage(cast(s32, width), cast(s32, height), pixelFormat)

        var result: #returntype
        result.init(cast(s32, width), cast(s32, height), pixelFormat)
        if not options.decodePixels
        {
            return result
        }

        result.allocPixels()
        var input: u64
        if channels == 4
        {
            input = try decodePayload!{4}(&result, buffer)
        }
        else
        {
            input = try decodePayload!{3}(&result, buffer)
        }

        let expectedEnd: [8] u8 = [0, 0, 0, 0, 0, 0, 0, 1]
        if input + EndMarkerSize != buffer.count
        {
            fail InvalidFormatError{"QOI data has bytes after the image payload"}
        }

        for i in EndMarkerSize where source[input + i] != expectedEnd[i]
        {
            fail InvalidFormatError{"QOI end marker is invalid"}
        }

        return result
    }
}
