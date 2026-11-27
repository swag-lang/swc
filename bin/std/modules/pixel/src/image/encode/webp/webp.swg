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
        Swag.assert(count <= 51)
        let mask = (1_u64 << count) - 1
        .bits     |= (value & mask) << .bitCount
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

    func(BGR: bool, ALPHA: bool) packRow(destination: [*] u32, source: const [*] u8, width: s32)
    {
        using Math.Simd

        #static if ALPHA and not BGR
        {
            Memory.copy(destination, source, cast(u64, width) * 4)
        }
        else
        {
            const Channels    = ALPHA ? 4 : 3
            const VectorWidth = ALPHA ? 4 : 6
            const R           = BGR ? 2 : 0
            const B           = BGR ? 0 : 2

            // Three-byte pixels need six input pixels before a sixteen-byte load.
            const BgrToRgba  = cast(U8x16, [2_u8, 1, 0, 0x80, 5, 4, 3, 0x80, 8, 7, 6, 0x80, 11, 10, 9, 0x80])
            const RgbToRgba  = cast(U8x16, [0_u8, 1, 2, 0x80, 3, 4, 5, 0x80, 6, 7, 8, 0x80, 9, 10, 11, 0x80])
            const BgraToRgba = cast(U8x16, [2_u8, 1, 0, 3, 6, 5, 4, 7, 10, 9, 8, 11, 14, 13, 12, 15])
            const Reorder    = ALPHA ? BgraToRgba : (BGR ? BgrToRgba : RgbToRgba)
            var x: s32
            while width - x >= VectorWidth
            {
                var rgba = cast #bit(U32x4, shuffle(load(source + x * Channels), Reorder))
                #static if not ALPHA
                {
                    rgba |= splat(0xFF000000_u32)
                }

                store(destination + x, rgba)
                x += 4
            }

            for i in x until width
            {
                let pixel = source + i * Channels
                let alpha = ALPHA ? pixel[3] : 0xFF
                destination[i] = cast(u32, pixel[R]) | (cast(u32, pixel[1]) << 8) |
                                 (cast(u32, pixel[B]) << 16) | (cast(u32, alpha) << 24)
            }
        }
    }

    func packPixels(image: Image, pixels: *Array!{u32})
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
            return shift
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
        let value = length - 1
        if length <= 4
        {
            return {LOSSLESS_LITERAL_CODES + value, 0, 0}
        }

        let high   = 31 - Math.leadingZeros(value)
        let width  = high - 1
        let symbol = 2 * high + ((value >> width) & 1)
        return {LOSSLESS_LITERAL_CODES + symbol, value & ((1_u32 << width) - 1), width}
    }

    #[Swag.Inline]
    func(RESIDUAL: bool) writeLength(writer: *EncodeBitWriter, length: u32)
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
                let limit = cast(u32, Math.min(4096_u64, pixels.count - index))
                let match = repeatedPixelMatch(data, index, limit, rowWidth)
                if match.length
                {
                    writeLength!{false}(writer, match.length)
                    writer.writeBits(match.above ? 0 : 1, 1)
                    index += match.length
                    continue
                }
            }
            else
            {
                if index and data[index] == data[index - 1]
                {
                    let limit  = cast(u32, Math.min(4096_u64, pixels.count - index))
                    let length = repeatedPixelCount(data + index, data[index - 1], limit)
                    writeLength!{RESIDUAL}(writer, length)
                    index += length
                    continue
                }
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

    func collectPalette(palette: *EncodePalette, pixels: const [..] u32)->bool
    {
        using Math.Simd

        let firstColor = pixels[0]
        let first      = splat(firstColor)
        discard palette.indexOf(firstColor)
        var cursor: u64
        while pixels.count - cursor >= 4 and allTrue(load(pixels.buffer + cursor) == first)
        {
            cursor += 4
        }

        while cursor < pixels.count and pixels[cursor] == firstColor
        {
            cursor += 1
        }

        if cursor == pixels.count
        {
            return true
        }

        var previous = pixels[cursor]
        discard palette.indexOf(previous)
        let second = splat(previous)
        cursor += 1
        while pixels.count - cursor >= 4
        {
            let next = load(pixels.buffer + cursor)
            if not allTrue((next == first) | (next == second))
            {
                break
            }

            cursor += 4
        }

        let firstRed  = firstColor & 0xFF
        let secondRed = previous & 0xFF
        if firstRed != secondRed
        {
            // Use the red component until different colors share its value.
            var byRed: [256] u16
            byRed[firstRed]  = 1
            byRed[secondRed] = 2
            while cursor < pixels.count
            {
                let color = pixels[cursor]
                let red   = color & 0xFF
                let entry = byRed[red]
                if entry
                {
                    if palette.colors[entry - 1] != color
                    {
                        break
                    }
                }
                else
                {
                    let entryIndex = palette.indexOf(color)
                    if entryIndex < 0
                    {
                        return false
                    }

                    byRed[red] = cast(u16, (entryIndex + 1))
                }

                cursor += 1
            }
        }

        for i in cursor until pixels.count
        {
            let color = pixels[i]
            if color == previous
            {
                continue
            }

            if palette.indexOf(color) < 0
            {
                return false
            }

            previous = color
        }

        return true
    }

    func writeConstantTrees(writer: *EncodeBitWriter, color: u32)
    {
        var channel = EncodeChannel{count: 1}
        for lane in [1, 0, 2, 3]
        {
            channel.values[0] = cast(u8, ((color >> (8 * lane)) & 0xFF))
            writeSimpleTree(writer, channel)
        }

        writeDistanceTree(writer)

        // Single-symbol trees can fill the image without any literal bits.
    }

    func writeColorImage(writer: *EncodeBitWriter, pixels: Array!{u32}, channels: EncodeChannels, topLevel: bool, rowWidth: u32 = 0)
    {
        writer.writeBits(0, 1)     // Color cache.
        if topLevel
        {
            writer.writeBits(0, 1)     // Huffman group map.
        }

        writeGreenTree(writer)
        writeByteTree(writer, channels.red)
        writeByteTree(writer, channels.blue)
        writeByteTree(writer, channels.alpha)
        if rowWidth
        {
            // The two plane codes refer to the pixels above and to the left.
            writeSimpleTree(writer, EncodeChannel{values: [0, 1], count: 2})
            writePixels!{false, true}(writer, pixels, channels, rowWidth)
        }
        else
        {
            writeDistanceTree(writer)
            writePixels!{false, false}(writer, pixels, channels)
        }
    }

    #[Swag.Inline]
    func predictedResidual(pixel, prediction: Math.Simd.U8x16)->Math.Simd.U8x16
    {
        using Math.Simd

        const Green = cast(U8x16, [1_u8, 0x80, 1, 0x80, 5, 0x80, 5, 0x80, 9, 0x80, 9, 0x80, 13, 0x80, 13, 0x80])
        let difference = pixel - prediction
        return difference - shuffle(difference, Green)
    }

    #[Swag.Inline]
    func predictedPixel(pixel, prediction: u32)->u32
    {
        using Math.Simd

        let residual = predictedResidual(cast #bit(U8x16, splat(pixel)), cast #bit(U8x16, splat(prediction)))
        return cast #bit(U32x4, residual)[0]
    }

    func applyVerticalPrediction(pixels: [*] u32, width, height: s32)
    {
        using Math.Simd

        // Work upwards so that the previous row still holds original pixels.
        var y = height - 1
        while y > 0
        {
            let row = pixels + cast(u64, y) * width
            let top = row - width
            var x: s32
            while width - x >= 4
            {
                let pixel      = cast #bit(U8x16, load(row + x))
                let prediction = cast #bit(U8x16, load(top + x))
                store(row + x, cast #bit(U32x4, predictedResidual(pixel, prediction)))
                x += 4
            }

            for column in x until width
            {
                row[column] = predictedPixel(row[column], top[column])
            }

            y -= 1
        }

        // VP8L predicts the very first pixel from opaque black and the
        // remainder of the first row from the pixel to the left.
        var x = width - 1
        while x > 0
        {
            pixels[x] = predictedPixel(pixels[x], pixels[x - 1])
            x         -= 1
        }

        pixels[0] = predictedPixel(pixels[0], 0xFF000000)
    }

    #[Swag.Inline]
    func channelWidth(channel: EncodeChannel)->u32
    {
        return channel.count < 3 ? channel.count - 1 : 8
    }

    #[Swag.Inline]
    func(RESIDUAL: bool) repeatCost(length: u32)->u32
    {
        if length == 0
        {
            return 0
        }

        let run = encodeRun(length)
        #static if RESIDUAL
        {
            return (WEBP_ENCODE_RESIDUAL_GREEN_CODES[run.symbol] >> 16) + run.width
        }
        else
        {
            return cast(u32, WEBP_ENCODE_GREEN_CODES[run.symbol] >> 9) + run.width
        }
    }

    func chooseColorStrategy(pixels: const [..] u32, channels: EncodeChannels, width: s32, hasAlpha: bool)->EncodeColorStrategy
    {
        const Windows    = 32_u32
        const WindowSize = 32_u32
        if pixels.count < 65536
        {
            return .Direct
        }

        let stride    = cast(u64, width)
        let data      = pixels.buffer
        let step      = (pixels.count - stride - WindowSize - 1) / Windows
        let rawColors = channelWidth(channels.red) + channelWidth(channels.blue) + channelWidth(channels.alpha)
        var rawCost, predictedCost: u32
        for window in Windows
        {
            let offset        = stride + 1 + window * step
            var previous      = data[offset - 1]
            var priorResidual = predictedPixel(previous, data[offset - 1 - stride])
            var rawRun, predictedRun: u32
            for index in offset until offset + WindowSize
            {
                let pixel    = data[index]
                let residual = predictedPixel(pixel, data[index - stride])
                if pixel == previous
                {
                    rawRun += 1
                }
                else
                {
                    let green = (pixel >> 8) & 0xFF
                    rawCost += repeatCost!{false}(rawRun) + rawColors + (WEBP_ENCODE_GREEN_CODES[green] >> 9)
                    rawRun  = 0
                }

                if residual == priorResidual
                {
                    predictedRun += 1
                }
                else
                {
                    predictedCost += repeatCost!{true}(predictedRun)
                    predictedCost += WEBP_ENCODE_RESIDUAL_GREEN_CODES[(residual >> 8) & 0xFF] >> 16
                    predictedCost += WEBP_ENCODE_RESIDUAL_COLOR_CODES[residual & 0xFF] >> 16
                    predictedCost += WEBP_ENCODE_RESIDUAL_COLOR_CODES[(residual >> 16) & 0xFF] >> 16
                    if hasAlpha
                    {
                        predictedCost += WEBP_ENCODE_RESIDUAL_COLOR_CODES[residual >> 24] >> 16
                    }

                    predictedRun = 0
                }

                previous      = pixel
                priorResidual = residual
            }

            rawCost       += repeatCost!{false}(rawRun)
            predictedCost += repeatCost!{true}(predictedRun)
        }

        if not hasAlpha and rawCost < 8 * Windows * WindowSize
        {
            // Images dominated by runs can reduce both size and decoding work
            // by copying the preceding row, without changing their literal codes.
            var aboveCost: u32
            for window in Windows
            {
                var index = stride + 1 + window * step
                let end   = index + WindowSize
                while index < end
                {
                    let match = repeatedPixelMatch(data, index, cast(u32, (end - index)), stride)
                    if match.length
                    {
                        aboveCost += repeatCost!{false}(match.length) + 1
                        index     += match.length
                    }
                    else
                    {
                        let green = (data[index] >> 8) & 0xFF
                        aboveCost += rawColors + (WEBP_ENCODE_GREEN_CODES[green] >> 9)
                        index     += 1
                    }
                }
            }

            if aboveCost * 8 < rawCost * 7
            {
                return .AboveMatches
            }
        }

        // The sampled reduction must cover the larger tree headers and
        // short-scale variation between sampled rows.
        return predictedCost * 8 < rawCost * 7 ? .Predicted : .Direct
    }

    func writeResidualTree(writer: *EncodeBitWriter, codes: const [..] u32)
    {
        writer.writeBits(0, 1)
        writer.writeBits(WEBP_ENCODE_CODE_LENGTH_ORDER.count - 4, 4)
        for symbol in WEBP_ENCODE_CODE_LENGTH_ORDER
        {
            writer.writeBits(symbol < 16 ? 4 : 0, 3)
        }

        writer.writeBits(0, 1)
        for code in codes
        {
            writer.writeHuffman(code >> 16, 4)
        }
    }

    func writePredictedImage(writer: *EncodeBitWriter, pixels: *Array!{u32}, width, height: s32, hasAlpha: bool)
    {
        writer.writeBits(1, 1)
        writer.writeBits(LOSSLESS_TRANSFORM_PREDICTOR, 2)
        writer.writeBits(7, 3)     // All 512-pixel tiles use predictor 2, the pixel above.
        writer.writeBits(0, 1)     // No color cache in the predictor map.
        writeConstantTrees(writer, 2 << 8)

        writer.writeBits(1, 1)
        writer.writeBits(LOSSLESS_TRANSFORM_SUBTRACT_GREEN, 2)
        writer.writeBits(0, 3)     // End transforms, no color cache or Huffman group map.
        writeResidualTree(writer, WEBP_ENCODE_RESIDUAL_GREEN_CODES)
        writeResidualTree(writer, WEBP_ENCODE_RESIDUAL_COLOR_CODES)
        writeResidualTree(writer, WEBP_ENCODE_RESIDUAL_COLOR_CODES)
        var channels: EncodeChannels
        if hasAlpha
        {
            writeResidualTree(writer, WEBP_ENCODE_RESIDUAL_COLOR_CODES)
        }
        else
        {
            channels.alpha.count = 1
            writeSimpleTree(writer, channels.alpha)
        }

        writeDistanceTree(writer)

        applyVerticalPrediction(cast([*] u32, pixels.storage()), width, height)
        writePixels!{true, false}(writer, pixels[], channels)
    }

    func writePalette(writer: *EncodeBitWriter, palette: *EncodePalette)
    {
        writer.writeBits(1, 1)
        writer.writeBits(LOSSLESS_TRANSFORM_COLOR_INDEXING, 2)
        writer.writeBits(palette.count - 1, 8)

        var deltas:   Array!{u32}
        var channels: EncodeChannels
        var previous: u32
        for i in palette.count
        {
            let color = palette.colors[i]
            var delta: u32
            for lane in 4
            {
                let shift  = 8 * lane
                let sample = ((color >> shift) - #wrap (previous >> shift)) & 0xFF
                delta |= sample << shift
            }

            deltas.add(delta)
            channels.red.add(cast(u8, (delta & 0xFF)))
            channels.blue.add(cast(u8, ((delta >> 16) & 0xFF)))
            channels.alpha.add(cast(u8, (delta >> 24)))
            previous = color
        }

        writeColorImage(writer, deltas, channels, false)
    }

    func paletteIndexChannel(palette: *EncodePalette, indices: *[256] u8)->s32
    {
        // A channel that distinguishes every color can index a byte table directly.
        for lane in 4
        {
            var used: [256] bool
            let shift  = 8 * lane
            var unique = true
            for index in palette.count
            {
                let value = (palette.colors[index] >> shift) & 0xFF
                if used[value]
                {
                    unique = false
                    break
                }

                used[value]      = true
                indices[][value] = cast(u8, index)
            }

            if unique
            {
                return cast(s32, shift)
            }
        }

        return -1
    }

    func packPalette(palette: *EncodePalette, pixels: const [..] u32, width, height, packedWidth: s32, bits: u32)->Array!{u8}
    {
        using Math.Simd

        var packed: Array!{u8}
        let count = cast(u64, packedWidth) * height
        packed.grow(count)
        packed.count = count
        let output    = cast([*] u8, packed.storage())
        let groupSize = 1_s32 << bits
        let indexBits = 8_u32 >> bits
        var previous  = pixels[0]
        var paletteIndex: u32

        let binaryColor = splat(palette.colors[1])

        var indices: [256] u8
        let channel = bits == 3 ? -1 : paletteIndexChannel(palette, &indices)

        let reuseRows = bits != 3 and width >= 32
        let rowBytes  = cast(u64, width) * 4
        for y in height
        {
            let inputRow  = pixels.buffer + cast(u64, y) * width
            let outputRow = output + cast(u64, y) * packedWidth
            if reuseRows and y
            {
                let above = inputRow - width
                if inputRow[0] == above[0] and
                   inputRow[width - 1] == above[width - 1] and
                   Memory.compare(inputRow, above, rowBytes) == 0
                {
                    Memory.copy(outputRow, outputRow - packedWidth, packedWidth)
                    continue
                }
            }

            if bits == 3
            {
                var x:     s32
                var index: s32
                while width - x >= 8
                {
                    let low  = bitmask(load(inputRow + x) == binaryColor)
                    let high = bitmask(load(inputRow + x + 4) == binaryColor)
                    outputRow[index] = cast(u8, (low | (high << 4)))
                    x     += 8
                    index += 1
                }

                if x < width
                {
                    let second = palette.colors[1]
                    var bitsRemaining: u32
                    for i in x until width
                    {
                        bitsRemaining |= cast(u32, inputRow[i] == second) << (i - x)
                    }

                    outputRow[index] = cast(u8, bitsRemaining)
                }

                continue
            }

            for group in packedWidth
            {
                let x    = cast(s32, group) * groupSize
                let span = Math.min(groupSize, width - x)
                var value: u32
                for i in span
                {
                    let color = inputRow[x + i]
                    if channel >= 0
                    {
                        paletteIndex = indices[(color >> channel) & 0xFF]
                    }
                    else if color != previous
                    {
                        paletteIndex = cast(u32, palette.indexOf(color))
                        previous     = color
                    }

                    value |= paletteIndex << (i * indexBits)
                }

                outputRow[group] = cast(u8, value)
            }
        }

        return packed
    }

    func writeMatchDistanceTree(writer: *EncodeBitWriter)
    {
        // Forty canonical codes use 24 five-bit codes and 16 six-bit codes.
        const CodeCount = 10
        writer.writeBits(0, 1)
        writer.writeBits(CodeCount - 4, 4)
        for i in CodeCount
        {
            let symbol = WEBP_ENCODE_CODE_LENGTH_ORDER[i]
            writer.writeBits(symbol == 5 or symbol == 6 ? 1 : 0, 3)
        }

        writer.writeBits(0, 1)
        for i in LOSSLESS_DISTANCE_CODES
        {
            writer.writeBits(i < 24 ? 0 : 1, 1)
        }
    }

    func writeMatchDistance(writer: *EncodeBitWriter, distance, width: u32)
    {
        // Use the plane distance for the pixel immediately above or to the left.
        let parameter = distance == 1 ? 2_u32 : (distance == width ? 1_u32 : distance + cast(u32, LOSSLESS_DISTANCE_MAP.count))
        let value     = parameter - 1
        if parameter <= 4
        {
            writer.writeHuffman(value, 5)
            return
        }

        let high      = 31 - Math.leadingZeros(value)
        let extraBits = high - 1
        let symbol    = 2 * high + ((value >> extraBits) & 1)
        if symbol < 24
        {
            writer.writeHuffman(symbol, 5)
        }
        else
        {
            writer.writeHuffman(symbol + 24, 6)
        }

        writer.writeBits(value & ((1_u32 << extraBits) - 1), extraBits)
    }

    #[Swag.Inline]
    func extendMatch(input, previous: const [*] u8, limit: u64)->u64
    {
        using Math.Simd

        var length = 4_u64
        while limit - length >= 16 and allTrue(load(input + length) == load(previous + length))
        {
            length += 16
        }

        while length < limit and input[length] == previous[length]
        {
            length += 1
        }

        return length
    }

    func findRowRepeat(packed: const [..] u8, width: s32, maxDistance: u64)->u64
    {
        let stride = cast(u64, width)
        let prefix = Math.min(4096_u64, 3 * stride)
        if prefix < 4 or packed.count < prefix + stride
        {
            return 0
        }

        let first = packed.buffer
        let key   = cast(const [*] u32, first)[0]
        let rows  = Math.min(maxDistance, packed.count - prefix) / stride
        for step in 1 until rows + 1
        {
            let offset = step * stride
            let probe  = first + offset
            if cast(const [*] u32, probe)[0] == key and extendMatch(probe, first, prefix) == prefix
            {
                return offset
            }
        }

        return 0
    }

    func writePackedMatches(writer: *EncodeBitWriter, packed: const [..] u8, width: s32)
    {
        const HashBits        = 12
        const MaximumDistance = (1_u64 << 20) - LOSSLESS_DISTANCE_MAP.count
        var lastPosition: [1 << HashBits] u32
        let data      = packed.buffer
        let rowRepeat = findRowRepeat(packed, width, MaximumDistance)
        var index:        u64
        while index < packed.count
        {
            let remaining = packed.count - index
            if remaining >= 4
            {
                let input    = data + index
                let key      = cast(const [*] u32, input)[0]
                let hash     = (key * #wrap 0x9E3779B1_u32) >> (32 - HashBits)
                let previous = lastPosition[hash]
                lastPosition[hash] = cast(u32, index + 1)
                let limit = Math.min(4096_u64, remaining)
                var length, distance: u64
                if rowRepeat and
                   index >= rowRepeat and
                   cast(const [*] u32, input - rowRepeat)[0] == key
                {
                    length   = extendMatch(input, input - rowRepeat, limit)
                    distance = rowRepeat
                }

                if length < limit and previous
                {
                    let probe = cast(u64, previous - 1)
                    let delta = index - probe
                    if delta <= MaximumDistance and cast(const [*] u32, data + probe)[0] == key
                    {
                        let amount = extendMatch(input, data + probe, limit)
                        if amount >= length
                        {
                            length   = amount
                            distance = delta
                        }
                    }
                }

                if length
                {
                    writeLength!{false}(writer, cast(u32, length))
                    writeMatchDistance(writer, cast(u32, distance), cast(u32, width))
                    index += length
                    continue
                }
            }

            writeGreenSymbol(writer, data[index])
            index += 1
        }
    }

    func writeIndexedImage(writer: *EncodeBitWriter, palette: *EncodePalette, pixels: Array!{u32}, width, height: s32)
    {
        writePalette(writer, palette)
        writer.writeBits(0, 1)     // End transforms.
        writer.writeBits(0, 1)     // Color cache.
        writer.writeBits(0, 1)     // Huffman group map.
        writeGreenTree(writer)
        let constant = EncodeChannel{count: 1}
        writeByteTree(writer, constant)
        writeByteTree(writer, constant)
        writeByteTree(writer, constant)
        writeMatchDistanceTree(writer)

        let bits        = palette.count <= 2 ? 3_u32 : (palette.count <= 4 ? 2_u32 : (palette.count <= 16 ? 1_u32 : 0_u32))
        let packedWidth = losslessTileCount(width, bits)
        let packed      = packPalette(palette, pixels.toSlice(), width, height, packedWidth, bits)
        writePackedMatches(writer, packed.toSlice(), packedWidth)
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
        if payload.count & 1
        {
            destination[Header.count + payload.count] = 0
        }
    }
}
