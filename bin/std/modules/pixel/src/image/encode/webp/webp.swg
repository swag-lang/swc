//! Format: WebP still-image encoder component.
//! Supported: Lossless VP8L output with alpha from 8-bit RGB/BGR source images up to 16384 pixels per dimension.
//! Not supported: Lossy VP8, animation, metadata chunks, and dimensions above 16384.
//! Role: This file owns RIFF chunk emission, lossless VP8L payloads, and top-level encoding.
//
#global namespace Webp

using Core, Core.Errors

const WEBP_ENCODE_MAX_DIMENSION        = 16384
const WEBP_ENCODE_GREEN_SHORT_SYMBOLS  = 232'u32
const WEBP_ENCODE_GREEN_LONG_CODE_BASE = 464'u32

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
        let count     = shortCode ? 8'u32 : 9'u32
        let code      = shortCode ? literal : WEBP_ENCODE_GREEN_LONG_CODE_BASE + literal - WEBP_ENCODE_GREEN_SHORT_SYMBOLS
        let reversed  = cast(u32, Math.reverse(cast(u16, code))) >> (16 - count)
        codes[symbol] = cast(u16, (reversed | (count << 9)))
    }

    return codes
}

struct EncodeBitWriter
{
    bytes:    Array'u8
    bits:     u64
    bitCount: u32
}

impl EncodeBitWriter
{
    #[Swag.Inline]
    mtd writeBits(value: u64, count: u32)
    {
        Swag.assert(count <= 33)
        let mask = (1'u64 << count) - 1
        .bits     |= (value & mask) << .bitCount
        .bitCount += count

        let completeBytes = .bitCount >> 3
        if completeBytes
        {
            // Leave room for the whole word, then expose only its complete bytes.
            let offset = .bytes.count
            if offset + 8 > .bytes.capacity do
                .bytes.grow(offset + 8)
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
        if .bitCount do
            .bytes.add(cast(u8, (.bits & 0xFF)))
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

        if value == .values[0] or (.count == 2 and value == .values[1]) do
            return
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
    colors: [16] u32
    slots:  [32] u8
    count:  u32
}

impl EncodePalette
{
    #[Swag.Inline]
    mtd indexOf(color: u32)->s32
    {
        var slot = (color * #wrap 0x9E3779B1'u32) >> 27
        while .slots[slot]
        {
            let index = .slots[slot] - 1
            if .colors[index] == color do
                return cast(s32, index)
            slot = (slot + 1) & 31
        }

        if .count == .colors.count do
            return -1
        let index = .count
        .colors[index] = color
        .count         += 1
        .slots[slot]   = cast(u8, .count)
        return cast(s32, index)
    }
}

// Encodes lossless VP8L WebP images in a RIFF container.
internal struct Encoder {}

impl Encoder
{
    func writeU32(result: *ConcatBuffer, value: u32)
    {
        result.addNative(cast(u8, (value & 0xFF)))
        result.addNative(cast(u8, ((value >> 8) & 0xFF)))
        result.addNative(cast(u8, ((value >> 16) & 0xFF)))
        result.addNative(cast(u8, (value >> 24)))
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
            const BgrToRgba  = cast(U8x16, [2'u8, 1, 0, 0x80, 5, 4, 3, 0x80, 8, 7, 6, 0x80, 11, 10, 9, 0x80])
            const RgbToRgba  = cast(U8x16, [0'u8, 1, 2, 0x80, 3, 4, 5, 0x80, 6, 7, 8, 0x80, 9, 10, 11, 0x80])
            const BgraToRgba = cast(U8x16, [2'u8, 1, 0, 3, 6, 5, 4, 7, 10, 9, 8, 11, 14, 13, 12, 15])
            const Reorder    = ALPHA ? BgraToRgba : (BGR ? BgrToRgba : RgbToRgba)
            var x: s32
            while width - x >= VectorWidth
            {
                var rgba = cast #bit(U32x4, shuffle(load(source + x * Channels), Reorder))
                #static if not ALPHA do
                    rgba |= splat(0xFF000000'u32)
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

    func packPixels(image: Image, pixels: *Array'u32)
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
            case .RGB8:  packRow'(false, false)(output, input, image.width)
            case .BGR8:  packRow'(true, false)(output, input, image.width)
            case .RGBA8: packRow'(false, true)(output, input, image.width)
            case .BGRA8: packRow'(true, true)(output, input, image.width)
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
            if index and pixel == previous do
                continue
            previous = pixel

            if channels.red.count < 3 do
                channels.red.add(cast(u8, (pixel & 0xFF)))
            if channels.blue.count < 3 do
                channels.blue.add(cast(u8, ((pixel >> 16) & 0xFF)))
            if hasAlphaChannel and channels.alpha.count < 3 do
                channels.alpha.add(cast(u8, (pixel >> 24)))
            if channels.red.count == 3 and
               channels.blue.count == 3 and
               (not hasAlphaChannel or channels.alpha.count == 3) do
                break
        }

        return channels.alpha.count > 1 or channels.alpha.values[0] != 0xFF
    }

    func writeComplexTreeHeader(writer: *EncodeBitWriter, includeNine: bool)
    {
        writer.writeBits(0, 1)
        let codeCount = includeNine ? 13'u32 : 12'u32
        writer.writeBits(codeCount - 4, 4)
        for i in codeCount
        {
            let symbol = WEBP_ENCODE_CODE_LENGTH_ORDER[i]
            let length = symbol == 8 or (includeNine and symbol == 9) ? 1'u32 : 0'u32
            writer.writeBits(length, 3)
        }

        writer.writeBits(0, 1)
    }

    func writeGreenTree(writer: *EncodeBitWriter)
    {
        writeComplexTreeHeader(writer, true)
        for WEBP_ENCODE_GREEN_SHORT_SYMBOLS do
            writer.writeHuffman(0, 1)
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
        if channel.count == 2 do
            writer.writeBits(channel.values[1], 8)
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
        if channel.count == 1 do
            return shift
        if channel.count == 2
        {
            codes[][channel.values[1]] = 1'u32 << shift
            return shift + 1
        }

        for symbol in 256 do
            codes[][symbol] = cast(u32, Math.reverse(cast(u8, symbol))) << shift
        return shift + 8
    }

    func writeLength(writer: *EncodeBitWriter, length: u32)
    {
        Swag.assert(length >= 1 and length <= 4096)
        let value = length - 1
        if length <= 4
        {
            writeGreenSymbol(writer, LOSSLESS_LITERAL_CODES + value)
            return
        }

        let high      = 31 - Math.leadingZeros(value)
        let extraBits = high - 1
        let next      = (value >> extraBits) & 1
        let symbol    = 2 * high + next
        writeGreenSymbol(writer, LOSSLESS_LITERAL_CODES + symbol)
        writer.writeBits(value & ((1'u32 << extraBits) - 1), extraBits)
    }

    func writePixels(writer: *EncodeBitWriter, pixels: Array'u32, channels: EncodeChannels)
    {
        var redCodes, blueCodes, alphaCodes: [256] u32
        let blueShift  = prepareChannel(&redCodes, channels.red, 0)
        let alphaShift = prepareChannel(&blueCodes, channels.blue, blueShift)
        let colorWidth = prepareChannel(&alphaCodes, channels.alpha, alphaShift)

        let data = cast(const [*] u32, pixels.storage())
        var index: u64
        while index < pixels.count
        {
            if index and data[index] == data[index - 1]
            {
                using Math.Simd

                let color    = data[index - 1]
                let repeated = splat(color)
                let limit    = cast(u32, Math.min(4096'u64, pixels.count - index))
                var length   = 1'u32
                while limit - length >= 4 and allTrue(load(data + index + length) == repeated) do
                    length += 4
                while length < limit and data[index + length] == color do
                    length += 1
                writeLength(writer, length)
                index += length
                continue
            }

            let pixel      = data[index]
            let red        = cast(u8, (pixel & 0xFF))
            let green      = cast(u8, ((pixel >> 8) & 0xFF))
            let blue       = cast(u8, ((pixel >> 16) & 0xFF))
            let alpha      = cast(u8, (pixel >> 24))
            let greenCode  = WEBP_ENCODE_GREEN_CODES[green]
            let greenWidth = cast(u32, greenCode >> 9)
            let colorCode  = redCodes[red] | blueCodes[blue] | alphaCodes[alpha]
            let bits       = cast(u64, greenCode & 0x1FF) | (cast(u64, colorCode) << greenWidth)
            writer.writeBits(bits, greenWidth + colorWidth)
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
        while pixels.count - cursor >= 4 and allTrue(load(pixels.buffer + cursor) == first) do
            cursor += 4
        while cursor < pixels.count and pixels[cursor] == firstColor do
            cursor += 1
        if cursor == pixels.count do
            return true

        var previous = pixels[cursor]
        discard palette.indexOf(previous)
        let second = splat(previous)
        cursor += 1
        while pixels.count - cursor >= 4
        {
            let next = load(pixels.buffer + cursor)
            if not allTrue((next == first) | (next == second)) do
                break
            cursor += 4
        }

        for i in cursor until pixels.count
        {
            let color = pixels[i]
            if color == previous do
                continue
            if palette.indexOf(color) < 0 do
                return false
            previous = color
        }

        return true
    }

    func writeSolidImage(writer: *EncodeBitWriter, color: u32)
    {
        writer.writeBits(0, 3)     // End transforms, no color cache or Huffman group map.
        var channel = EncodeChannel{count: 1}
        for lane in [1, 0, 2, 3]
        {
            channel.values[0] = cast(u8, ((color >> (8 * lane)) & 0xFF))
            writeSimpleTree(writer, channel)
        }

        writeDistanceTree(writer)

        // Single-symbol trees can fill the image without any literal bits.
    }

    func writeColorImage(writer: *EncodeBitWriter, pixels: Array'u32, channels: EncodeChannels, topLevel: bool)
    {
        writer.writeBits(0, 1)     // Color cache.
        if topLevel do
            writer.writeBits(0, 1)     // Huffman group map.
        writeGreenTree(writer)
        writeByteTree(writer, channels.red)
        writeByteTree(writer, channels.blue)
        writeByteTree(writer, channels.alpha)
        writeDistanceTree(writer)
        writePixels(writer, pixels, channels)
    }

    func writePalette(writer: *EncodeBitWriter, palette: *EncodePalette)
    {
        writer.writeBits(1, 1)
        writer.writeBits(LOSSLESS_TRANSFORM_COLOR_INDEXING, 2)
        writer.writeBits(palette.count - 1, 8)

        var deltas:   Array'u32
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

    func packPalette(palette: *EncodePalette, pixels: const [..] u32, width, height, packedWidth: s32, bits: u32)->Array'u8
    {
        using Math.Simd

        var packed: Array'u8
        let count = cast(u64, packedWidth) * height
        packed.grow(count)
        packed.count = count
        let output    = cast([*] u8, packed.storage())
        let groupSize = 1's32 << bits
        let indexBits = 8'u32 >> bits
        var previous  = pixels[0]
        var paletteIndex: u32

        let binaryColor = splat(palette.colors[1])

        for y in height
        {
            let inputRow  = pixels.buffer + cast(u64, y) * width
            let outputRow = output + cast(u64, y) * packedWidth
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
                    for i in x until width do
                        bitsRemaining |= cast(u32, inputRow[i] == second) << (i - x)
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
                    if color != previous
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
        for i in LOSSLESS_DISTANCE_CODES do
            writer.writeBits(i < 24 ? 0 : 1, 1)
    }

    func writeMatchDistance(writer: *EncodeBitWriter, distance, width: u32)
    {
        // Use the plane distance for the pixel immediately above or to the left.
        let parameter = distance == 1 ? 2'u32 : (distance == width ? 1'u32 : distance + cast(u32, LOSSLESS_DISTANCE_MAP.count))
        let value     = parameter - 1
        if parameter <= 4
        {
            writer.writeHuffman(value, 5)
            return
        }

        let high      = 31 - Math.leadingZeros(value)
        let extraBits = high - 1
        let symbol    = 2 * high + ((value >> extraBits) & 1)
        if symbol < 24 do
            writer.writeHuffman(symbol, 5)
        else do
            writer.writeHuffman(symbol + 24, 6)
        writer.writeBits(value & ((1'u32 << extraBits) - 1), extraBits)
    }

    #[Swag.Inline]
    func extendMatch(input, previous: const [*] u8, limit: u64)->u64
    {
        using Math.Simd

        var length = 4'u64
        while limit - length >= 16 and allTrue(load(input + length) == load(previous + length)) do
            length += 16
        while length < limit and input[length] == previous[length] do
            length += 1
        return length
    }

    func findRowRepeat(packed: const [..] u8, width: s32, maxDistance: u64)->u64
    {
        let stride = cast(u64, width)
        let prefix = Math.min(4096'u64, 3 * stride)
        if prefix < 4 or packed.count < prefix + stride do
            return 0

        let first     = packed.buffer
        let key       = cast(const [*] u32, first)[0]
        let available = Math.min(maxDistance, packed.count - prefix) / stride
        let rows      = Math.min(128'u64, available)
        for step in 1 until rows + 1
        {
            let offset = step * stride
            let probe  = first + offset
            if cast(const [*] u32, probe)[0] == key and extendMatch(probe, first, prefix) == prefix do
                return offset
        }

        return 0
    }

    func writePackedMatches(writer: *EncodeBitWriter, packed: const [..] u8, width: s32)
    {
        const HashBits        = 12
        const MaximumDistance = (1'u64 << 20) - LOSSLESS_DISTANCE_MAP.count
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
                let hash     = (key * #wrap 0x9E3779B1'u32) >> (32 - HashBits)
                let previous = lastPosition[hash]
                lastPosition[hash] = cast(u32, index + 1)
                let limit = Math.min(4096'u64, remaining)
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
                    writeLength(writer, cast(u32, length))
                    writeMatchDistance(writer, cast(u32, distance), cast(u32, width))
                    index += length
                    continue
                }
            }

            writeGreenSymbol(writer, data[index])
            index += 1
        }
    }

    func writeIndexedImage(writer: *EncodeBitWriter, palette: *EncodePalette, pixels: Array'u32, width, height: s32)
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

        let bits        = palette.count <= 2 ? 3'u32 : (palette.count <= 4 ? 2'u32 : 1'u32)
        let packedWidth = losslessTileCount(width, bits)
        let packed      = packPalette(palette, pixels.toSlice(), width, height, packedWidth, bits)
        writePackedMatches(writer, packed.toSlice(), packedWidth)
    }

    func encodeLossless(image: Image)->Array'u8
    {
        var pixels:   Array'u32
        var channels: EncodeChannels
        packPixels(image, &pixels)

        var palette: EncodePalette
        let indexed  = pixels.count >= 1024 and collectPalette(&palette, pixels.toSlice())
        var hasAlpha = false
        if indexed
        {
            for i in palette.count do
                hasAlpha = hasAlpha or (palette.colors[i] >> 24) != 0xFF
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
            if palette.count == 1 do
                writeSolidImage(&writer, palette.colors[0])
            else do
                writeIndexedImage(&writer, &palette, pixels, image.width, image.height)
        }
        else
        {
            writer.writeBits(0, 1)
            writeColorImage(&writer, pixels, channels, true)
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
           image.pixels.count != image.byteCount do
            fail InvalidFormatError{"WebP encoder needs a non-empty image"}
        if image.width > WEBP_ENCODE_MAX_DIMENSION or image.height > WEBP_ENCODE_MAX_DIMENSION do
            fail UnsupportedFormatError{"WebP lossless dimensions cannot exceed 16384 pixels"}
        if image.pixelFormat != .RGB8 and
           image.pixelFormat != .BGR8 and
           image.pixelFormat != .RGBA8 and
           image.pixelFormat != .BGRA8 do
            fail UnsupportedFormatError{"unsupported pixel format"}

        let expectedBytes = cast(u64, image.width) * image.height * image.bytesPerPixel
        if image.pixels.count < expectedBytes do
            fail InvalidFormatError{"WebP image pixel buffer ends before its declared dimensions"}

        let payload    = Encoder.encodeLossless(image)
        let paddedSize = payload.count + (payload.count & 1)
        if paddedSize > Swag.U32.Max - 12 do
            fail UnsupportedFormatError{"WebP encoded data does not fit in a RIFF chunk"}

        result.addBytes("RIFF")
        Encoder.writeU32(result, cast(u32, (4 + 8 + paddedSize)))
        result.addBytes("WEBP")
        result.addBytes("VP8L")
        Encoder.writeU32(result, cast(u32, payload.count))
        result.addBytes(payload.toSlice())
        if payload.count & 1 do
            result.addNative(0'u8)
    }
}
