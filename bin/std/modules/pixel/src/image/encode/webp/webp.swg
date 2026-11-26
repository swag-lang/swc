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

    func collectPixels(image: Image, pixels: *Array'u32, channels: *EncodeChannels)->bool
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

        let hasAlphaChannel = image.bytesPerPixel == 4
        if not hasAlphaChannel
        {
            channels.alpha.values[0] = 0xFF
            channels.alpha.count     = 1
        }

        var previous: u32
        for index in pixelCount
        {
            let pixel = destination[index]
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

    func encodeLossless(image: Image)->Array'u8
    {
        var pixels:   Array'u32
        var channels: EncodeChannels
        let hasAlpha = collectPixels(image, &pixels, &channels)

        var writer: EncodeBitWriter
        writer.writeBits(0x2F, 8)
        writer.writeBits(cast(u32, image.width) - 1, 14)
        writer.writeBits(cast(u32, image.height) - 1, 14)
        writer.writeBits(hasAlpha ? 1 : 0, 1)
        writer.writeBits(0, 3)

        writer.writeBits(0, 1)
        writer.writeBits(0, 1)
        writer.writeBits(0, 1)
        writeGreenTree(&writer)
        writeByteTree(&writer, channels.red)
        writeByteTree(&writer, channels.blue)
        writeByteTree(&writer, channels.alpha)
        writeDistanceTree(&writer)
        writePixels(&writer, pixels, channels)
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
