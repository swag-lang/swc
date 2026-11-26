//! Format: WebP still-image encoder component.
//! Supported: Lossless VP8L output with alpha from 8-bit RGB/BGR source images up to 16384 pixels per dimension.
//! Not supported: Lossy VP8, animation, metadata chunks, and dimensions above 16384.
//! Role: This file owns RIFF chunk emission, lossless VP8L payloads, and top-level encoding.
//
#global namespace Webp

using Core, Core.Errors

const WEBP_ENCODE_MAX_DIMENSION        = 16384
const WEBP_ENCODE_GREEN_SHORT_SYMBOLS  = 232_u32
const WEBP_ENCODE_GREEN_LONG_CODE_BASE = 464_u32

const WEBP_ENCODE_CODE_LENGTH_ORDER: [19] u8 = [
    17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

private const WEBP_ENCODE_GREEN_CODES = #run buildGreenCodes()

private func buildGreenCodes()->[LOSSLESS_LITERAL_CODES + LOSSLESS_LENGTH_CODES] u16
{
    var codes: #returntype
    for symbol in codes.count
    {
        let literal   = cast(u32, symbol)
        let shortCode = literal < WEBP_ENCODE_GREEN_SHORT_SYMBOLS
        let count     = shortCode ? 8_u32 : 9_u32
        let code      = shortCode ? literal : WEBP_ENCODE_GREEN_LONG_CODE_BASE + literal - WEBP_ENCODE_GREEN_SHORT_SYMBOLS
        let reversed  = cast(u32, Math.reverse(cast(u16, code))) >> (16 - count)
        codes[symbol] = cast(u16, (reversed | (count << 9)))
    }

    return codes
}

private const WEBP_ENCODE_RESIDUAL_COLOR_CODES = #run buildResidualCodes!{false, LOSSLESS_LITERAL_CODES}()
private const WEBP_ENCODE_RESIDUAL_GREEN_CODES = #run buildResidualCodes!{true, LOSSLESS_LITERAL_CODES + LOSSLESS_LENGTH_CODES}()

private func(GREEN: bool, Count: u32) buildResidualCodes()->[Count] u32
{
    // Short codes cover small signed channel differences. Green also carries
    // the run-length alphabet, whose first few symbols represent short runs.
    const ColorWidths: [7] u32 = [2, 3, 4, 6, 8, 11, 12]
    const ColorEnd:    [7] u32 = [1, 3, 7, 15, 31, 62, 256]
    const GreenWidths: [9] u32 = [3, 4, 5, 6, 7, 8, 10, 14, 15]
    const GreenEnd:    [9] u32 = [1, 3, 7, 15, 31, 63, 127, 238, 256]

    var widths: [Count] u32
    for symbol in LOSSLESS_LITERAL_CODES
    {
        let rank = symbol < 128 ? 2 * symbol : 2 * (256 - symbol) - 1
        #static if GREEN
        {
            for index in GreenEnd.count
            {
                if rank < GreenEnd[index]
                {
                    widths[symbol] = GreenWidths[index]
                    break
                }
            }
        }
        else
        {
            for index in ColorEnd.count
            {
                if rank < ColorEnd[index]
                {
                    widths[symbol] = ColorWidths[index]
                    break
                }
            }
        }
    }

    #static if GREEN
    {
        const LengthWidths = [3_u32, 5, 7, 7, 9, 9, 9, 9]
        for index in LOSSLESS_LENGTH_CODES
        {
            widths[LOSSLESS_LITERAL_CODES + index] = index < LengthWidths.count ? LengthWidths[index] : 15
        }
    }

    var counts, next: [16] u32
    for width in widths
    {
        counts[width] += 1
    }

    for width in 1 until counts.count
    {
        next[width] = (next[width - 1] + counts[width - 1]) << 1
    }

    Swag.assert(next[15] + counts[15] == 1 << 15)

    var result: #returntype
    for symbol in result.count
    {
        let width = widths[symbol]
        let bits  = cast(u32, Math.reverse(cast(u16, next[width]))) >> (16 - width)
        result[symbol] = bits | (width << 16)
        next[width]    += 1
    }

    return result
}

enum EncodeColorStrategy
{
    Direct
    AboveMatches
    Predicted
}

struct EncodePixelMatch
{
    length: u32
    above:  bool
}

struct EncodeRun
{
    symbol: u32
    extra:  u32
    width:  u32
}

struct EncodeBitWriter
{
    bytes:    Array!{u8}
    bits:     u64
    bitCount: u32
}

impl EncodeBitWriter
{
    #[Swag.Inline]
    mtd writeBits(value: u64, count: u32)
    {
        Swag.assert(count <= 32)
        let mask = count == 32 ? 0xFFFFFFFF_u64 : ((1_u64 << count) - 1)
        .bits     |= (cast(u64, value) & mask) << .bitCount
        .bitCount += count

        let completeBytes = .bitCount >> 3
        if completeBytes
        {
            // Leave room for the whole word, then expose only its complete bytes.
            let offset = .bytes.count
            if offset + 8 > .bytes.capacity
            {
                .bytes.grow(offset + 8)
            }

            cast([*] u64, (.bytes.storage() + offset))[0] = .bits
            .bytes.count = offset + completeBytes
            .bits        >>= completeBytes * 8
            .bitCount    &= 7
        }
    }

    #[Swag.Inline]
    mtd writeHuffman(code, count: u32)
    {
        Swag.assert(count <= 16)

        // Canonical codes are emitted most significant bit first in the little-endian writer.
        let reversed = cast(u32, Math.reverse(cast(u16, code))) >> (16 - count)
        .writeBits(reversed, count)
    }

    mtd finish()
    {
        if .bitCount
        {
            .bytes.add(cast(u8, (.bits & 0xFF)))
        }

        .bits     = 0
        .bitCount = 0
    }
}

struct EncodeChannel
{
    values: [2] u8
    count:  u8
}

impl EncodeChannel
{
    mtd add(value: u8)
    {
        if .count == 0
        {
            .values[0] = value
            .count     = 1
            return
        }

        if value == .values[0] or (.count == 2 and value == .values[1])
        {
            return
        }

        if .count == 1
        {
            .values[1] = value
            .count     = 2
            return
        }

        .count = 3
    }
}

struct EncodeChannels
{
    red:   EncodeChannel
    blue:  EncodeChannel
    alpha: EncodeChannel
}

struct EncodePalette
{
    colors: [256] u32
    slots:  [512] u16
    count:  u32
}

impl EncodePalette
{
    #[Swag.Inline]
    mtd indexOf(color: u32)->s32
    {
        var slot = (color * #wrap 0x9E3779B1_u32) >> 23
        while .slots[slot]
        {
            let index = .slots[slot] - 1
            if .colors[index] == color
            {
                return cast(s32, index)
            }

            slot = (slot + 1) & 511
        }

        if .count == .colors.count
        {
            return -1
        }

        let index = .count
        .colors[index] = color
        .count         += 1
        .slots[slot]   = cast(u16, .count)
        return cast(s32, index)
    }
}

// Encodes lossless VP8L WebP images in a RIFF container.
internal struct Encoder {}

impl Encoder
{
    func writeU32(destination: [*] u8, value: u32)
    {
        destination[0] = cast(u8, (value & 0xFF))
        destination[1] = cast(u8, ((value >> 8) & 0xFF))
        destination[2] = cast(u8, ((value >> 16) & 0xFF))
        destination[3] = cast(u8, (value >> 24))
    }

    func collectPixels(image: Image, pixels: *Array!{u32}, channels: *EncodeChannels)->bool
    {
        let pixelCount = cast(u64, image.width) * image.height
        pixels.grow(pixelCount)
        pixels.count = pixelCount
        let destination = cast([*] u32, pixels.storage())
        let source      = cast(const [*] u8, image.pixels.storage())

        for y in image.height
        {
            let input  = source + cast(u64, (image.height - y - 1)) * image.rowStride
            let output = destination + cast(u64, y) * image.width
            switch image.pixelFormat
            {
            case .RGB8:  packRow!{false, false}(output, input, image.width)
            case .BGR8:  packRow!{true, false}(output, input, image.width)
            case .RGBA8: packRow!{false, true}(output, input, image.width)
            case .BGRA8: packRow!{true, true}(output, input, image.width)
            default:     unreachable
            }
        }
    }

    func collectChannels(pixels: const [..] u32, hasAlphaChannel: bool, channels: *EncodeChannels)->bool
    {
        if not hasAlphaChannel
        {
            channels.alpha.values[0] = 0xFF
            channels.alpha.count     = 1
        }

        var previous: u32
        for index in pixels.count
        {
            let pixel = pixels[index]
            if index and pixel == previous
            {
                continue
            }

            previous = pixel

            if channels.red.count < 3
            {
                channels.red.add(cast(u8, (pixel & 0xFF)))
            }

            if channels.blue.count < 3
            {
                channels.blue.add(cast(u8, ((pixel >> 16) & 0xFF)))
            }

            if hasAlphaChannel and channels.alpha.count < 3
            {
                channels.alpha.add(cast(u8, (pixel >> 24)))
            }

            if channels.red.count == 3 and
               channels.blue.count == 3 and
               (not hasAlphaChannel or channels.alpha.count == 3)
            {
                break
            }
        }

        return channels.alpha.count > 1 or channels.alpha.values[0] != 0xFF
    }

    func writeComplexTreeHeader(writer: *EncodeBitWriter, includeNine: bool)
    {
        writer.writeBits(0, 1)
        let codeCount = includeNine ? 13_u32 : 12_u32
        writer.writeBits(codeCount - 4, 4)
        for i in codeCount
        {
            let symbol = WEBP_ENCODE_CODE_LENGTH_ORDER[i]
            let length = symbol == 8 or (includeNine and symbol == 9) ? 1_u32 : 0_u32
            writer.writeBits(length, 3)
        }

        writer.writeBits(0, 1)
    }

    func writeGreenTree(writer: *EncodeBitWriter)
    {
        writeComplexTreeHeader(writer, true)
        for WEBP_ENCODE_GREEN_SHORT_SYMBOLS
        {
            writer.writeHuffman(0, 1)
        }

        var symbol = WEBP_ENCODE_GREEN_SHORT_SYMBOLS
        while symbol < LOSSLESS_LITERAL_CODES + LOSSLESS_LENGTH_CODES
        {
            writer.writeHuffman(1, 1)
            symbol += 1
        }
    }

    func writeSimpleTree(writer: *EncodeBitWriter, channel: EncodeChannel)
    {
        writer.writeBits(1, 1)
        writer.writeBits(channel.count - 1, 1)
        let firstIsLong = channel.values[0] > 1
        writer.writeBits(firstIsLong ? 1 : 0, 1)
        writer.writeBits(channel.values[0], firstIsLong ? 8 : 1)
        if channel.count == 2
        {
            writer.writeBits(channel.values[1], 8)
        }
    }

    func writeByteTree(writer: *EncodeBitWriter, channel: EncodeChannel)
    {
        if channel.count <= 2
        {
            writeSimpleTree(writer, channel)
            return
        }

        writeComplexTreeHeader(writer, false)
    }

    func writeDistanceTree(writer: *EncodeBitWriter)
    {
        var channel: EncodeChannel
        channel.values[0] = 1
        channel.count     = 1
        writeSimpleTree(writer, channel)
    }

    func writeGreenSymbol(writer: *EncodeBitWriter, symbol: u32)
    {
        let code = WEBP_ENCODE_GREEN_CODES[symbol]
        writer.writeBits(code & 0x1FF, cast(u32, code >> 9))
    }

    func prepareChannel(codes: *[256] u32, channel: EncodeChannel, shift: u32)->u32
    {
        if channel.count == 1
        {
            return
        }

        if channel.count == 2
        {
            codes[][channel.values[1]] = 1_u32 << shift
            return shift + 1
        }

        for symbol in 256
        {
            codes[][symbol] = cast(u32, Math.reverse(cast(u8, symbol))) << shift
        }

        return shift + 8
    }

    #[Swag.Inline]
    func encodeRun(length: u32)->EncodeRun
    {
        Swag.assert(length >= 1 and length <= 4096)
        for symbol in LOSSLESS_LENGTH_CODES
        {
            var base:      u32
            var extraBits: u32
            if symbol < 4
            {
                base = cast(u32, symbol) + 1
            }
            else
            {
                extraBits = (cast(u32, symbol) - 2) >> 1
                base      = (2 + (cast(u32, symbol) & 1)) << extraBits
                base      += 1
            }

            let last = base + (extraBits ? (1_u32 << extraBits) - 1 : 0)
            if length < base or length > last
            {
                continue
            }

            writeGreenSymbol(writer, LOSSLESS_LITERAL_CODES + cast(u32, symbol))
            if extraBits
            {
                writer.writeBits(length - base, extraBits)
            }

            return
        }

        unreachable
    }

    func writePixels(writer: *EncodeBitWriter, pixels: Array!{u32}, channels: EncodeChannels)
    {
        let run = encodeRun(length)
        #static if RESIDUAL
        {
            let code = WEBP_ENCODE_RESIDUAL_GREEN_CODES[run.symbol]
            writer.writeBits(code & 0xFFFF, code >> 16)
        }
        else
        {
            writeGreenSymbol(writer, run.symbol)
        }

        if run.width
        {
            writer.writeBits(run.extra, run.width)
        }
    }

    #[Swag.Inline]
    func repeatedPixelCount(data: const [*] u32, color, limit: u32)->u32
    {
        using Math.Simd

        let repeated = splat(color)
        var length   = 1_u32
        while limit - length >= 4
        {
            let different = bitmask(load(data + length) == repeated) ^ 0xF
            if different
            {
                return length + Math.trailingZeros(different)
            }

            length += 4
        }

        while length < limit and data[length] == color
        {
            length += 1
        }

        return length
    }

    #[Swag.Inline]
    func repeatedPixelMatch(data: const [*] u32, index: u64, limit: u32, width: u64)->EncodePixelMatch
    {
        using Math.Simd

        let runStart = data + index
        var candidate: EncodePixelMatch
        if index and runStart[0] == data[index - 1]
        {
            candidate.length = repeatedPixelCount(runStart, runStart[0], limit)
        }

        if index < width or limit < 2 or candidate.length == limit
        {
            return candidate
        }

        let aboveStart = runStart - width
        if runStart[0] != aboveStart[0] or runStart[1] != aboveStart[1]
        {
            return candidate
        }

        var length = 2_u32
        while limit - length >= 4
        {
            let different = bitmask(load(runStart + length) == load(aboveStart + length)) ^ 0xF
            if different
            {
                length += Math.trailingZeros(different)
                return length > candidate.length ? EncodePixelMatch{length, true} : candidate
            }

            length += 4
        }

        while length < limit and runStart[length] == aboveStart[length]
        {
            length += 1
        }

        return length > candidate.length ? EncodePixelMatch{length, true} : candidate
    }

    func(RESIDUAL: bool, ROWS: bool) writePixels(writer: *EncodeBitWriter, pixels: Array!{u32}, channels: EncodeChannels, rowWidth: u32 = 0)
    {
        #static if not RESIDUAL
        {
            var redCodes, blueCodes, alphaCodes: [256] u32
            let blueShift  = prepareChannel(&redCodes, channels.red, 0)
            let alphaShift = prepareChannel(&blueCodes, channels.blue, blueShift)
            let colorWidth = prepareChannel(&alphaCodes, channels.alpha, alphaShift)
        }

        let data = cast(const [*] u32, pixels.storage())
        var index: u64
        while index < pixels.count
        {
            #static if ROWS
            {
                var length = 1_u32
                while length < 4096 and
                      index + length < pixels.count and
                      data[index + length] == data[index - 1]
                {
                    length += 1
                }

                writeLength(writer, length)
                index += length
                continue
            }

            let pixel = data[index]
            let red   = cast(u8, (pixel & 0xFF))
            let green = cast(u8, ((pixel >> 8) & 0xFF))
            let blue  = cast(u8, ((pixel >> 16) & 0xFF))
            let alpha = cast(u8, (pixel >> 24))
            #static if RESIDUAL
            {
                let greenCode  = WEBP_ENCODE_RESIDUAL_GREEN_CODES[green]
                let redCode    = WEBP_ENCODE_RESIDUAL_COLOR_CODES[red]
                let blueCode   = WEBP_ENCODE_RESIDUAL_COLOR_CODES[blue]
                let alphaCode  = channels.alpha.count == 1 ? 0 : WEBP_ENCODE_RESIDUAL_COLOR_CODES[alpha]
                let redShift   = greenCode >> 16
                let blueShift  = redShift + (redCode >> 16)
                let alphaShift = blueShift + (blueCode >> 16)
                let bits       = cast(u64, greenCode & 0xFFFF) |
                                 (cast(u64, redCode & 0xFFFF) << redShift) |
                                 (cast(u64, blueCode & 0xFFFF) << blueShift) |
                                 (cast(u64, alphaCode & 0xFFFF) << alphaShift)
                writer.writeBits(bits, alphaShift + (alphaCode >> 16))
            }
            else
            {
                let greenCode  = WEBP_ENCODE_GREEN_CODES[green]
                let greenWidth = cast(u32, greenCode >> 9)
                let colorCode  = redCodes[red] | blueCodes[blue] | alphaCodes[alpha]
                let bits       = cast(u64, greenCode & 0x1FF) | (cast(u64, colorCode) << greenWidth)
                writer.writeBits(bits, greenWidth + colorWidth)
            }

            index += 1
        }
    }

    func encodeLossless(image: Image)->Array!{u8}
    {
        var pixels:   Array!{u32}
        var channels: EncodeChannels
        packPixels(image, &pixels)

        var palette: EncodePalette
        let indexed  = pixels.count >= 1024 and collectPalette(&palette, pixels.toSlice())
        var hasAlpha = false
        if indexed
        {
            for i in palette.count
            {
                hasAlpha = hasAlpha or (palette.colors[i] >> 24) != 0xFF
            }
        }
        else
        {
            hasAlpha = collectChannels(pixels.toSlice(), image.bytesPerPixel == 4, &channels)
        }

        var writer: EncodeBitWriter
        writer.writeBits(0x2F, 8)
        writer.writeBits(cast(u32, image.width) - 1, 14)
        writer.writeBits(cast(u32, image.height) - 1, 14)
        writer.writeBits(hasAlpha ? 1 : 0, 1)
        writer.writeBits(0, 3)

        if indexed
        {
            if palette.count == 1
            {
                writer.writeBits(0, 3)     // End transforms, no color cache or Huffman group map.
                writeConstantTrees(&writer, palette.colors[0])
            }
            else
            {
                writeIndexedImage(&writer, &palette, pixels, image.width, image.height)
            }
        }
        else
        {
            let strategy = chooseColorStrategy(pixels.toSlice(), channels, image.width, hasAlpha)
            if strategy == .Predicted
            {
                writePredictedImage(&writer, &pixels, image.width, image.height, hasAlpha)
            }
            else
            {
                writer.writeBits(0, 1)     // End transforms.
                let rowWidth = strategy == .AboveMatches ? cast(u32, image.width) : 0
                writeColorImage(&writer, pixels, channels, true, rowWidth)
            }
        }

        writer.finish()
        return writer.bytes
    }
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"WebP - Google WebP", ".webp"}

    mtd impl encode(result: *ConcatBuffer, image: Image, _: any?) fail
    {
        if image.width <= 0 or
           image.height <= 0 or
           not image.isValid() or
           image.pixels.count != image.byteCount
        {
            fail InvalidFormatError{"WebP encoder needs a non-empty image"}
        }

        if image.width > WEBP_ENCODE_MAX_DIMENSION or image.height > WEBP_ENCODE_MAX_DIMENSION
        {
            fail UnsupportedFormatError{"WebP lossless dimensions cannot exceed 16384 pixels"}
        }

        if image.pixelFormat != .RGB8 and
           image.pixelFormat != .BGR8 and
           image.pixelFormat != .RGBA8 and
           image.pixelFormat != .BGRA8
        {
            fail UnsupportedFormatError{"unsupported pixel format"}
        }

        let expectedBytes = cast(u64, image.width) * image.height * image.bytesPerPixel
        if image.pixels.count < expectedBytes
        {
            fail InvalidFormatError{"WebP image pixel buffer ends before its declared dimensions"}
        }

        let payload    = Encoder.encodeLossless(image)
        let paddedSize = payload.count + (payload.count & 1)
        if paddedSize > Swag.U32.Max - 12
        {
            fail UnsupportedFormatError{"WebP encoded data does not fit in a RIFF chunk"}
        }

        const Header: [20] u8 = ['R', 'I', 'F', 'F', 0, 0, 0, 0, 'W', 'E', 'B', 'P', 'V', 'P', '8', 'L', 0, 0, 0, 0]

        // Write one bucket so encodeToBytes can transfer its storage.
        let destination = result.reserveInPlace(Header.count + paddedSize)
        Memory.copy(destination, &Header[0], Header.count)
        Encoder.writeU32(destination + 4, cast(u32, (4 + 8 + paddedSize)))
        Encoder.writeU32(destination + 16, cast(u32, payload.count))
        Memory.copy(destination + Header.count, payload.storage(), payload.count)
        if payload.count & 1 do
            destination[Header.count + payload.count] = 0
    }
}
