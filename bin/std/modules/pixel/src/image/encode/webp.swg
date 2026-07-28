#global namespace Webp

using Core, Core.Errors

const WEBP_ENCODE_MAX_DIMENSION        = 16384
const WEBP_ENCODE_GREEN_SHORT_SYMBOLS  = 232'u32
const WEBP_ENCODE_GREEN_LONG_CODE_BASE = 464'u32

const WEBP_ENCODE_CODE_LENGTH_ORDER: [19] u8 = [
    17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    ]

struct EncodeBitWriter
{
    bytes:    Array'u8
    bits:     u64
    bitCount: u32
}

impl EncodeBitWriter
{
    mtd writeBits(value: u32, count: u32)
    {
        Debug.assert(count <= 32)
        let mask = count == 32 ? 0xFFFFFFFF'u64 : ((1'u64 << count) - 1)
        .bits     |= (cast(u64) value & mask) << .bitCount
        .bitCount += count

        while .bitCount >= 8
        {
            .bytes.add(cast(u8) (.bits & 0xFF))
            .bits     >>= 8
            .bitCount -= 8
        }
    }

    mtd writeHuffman(code, count: u32)
    {
        var remaining = count
        while remaining
        {
            remaining -= 1
            .writeBits((code >> remaining) & 1, 1)
        }
    }

    mtd finish()
    {
        if .bitCount do
            .bytes.add(cast(u8) (.bits & 0xFF))
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

public struct Encoder {}

impl Encoder
{
    func writeU32(result: *ConcatBuffer, value: u32)
    {
        result.addNative(cast(u8) (value & 0xFF))
        result.addNative(cast(u8) ((value >> 8) & 0xFF))
        result.addNative(cast(u8) ((value >> 16) & 0xFF))
        result.addNative(cast(u8) (value >> 24))
    }

    func collectPixels(image: Image, pixels: *Array'u32, channels: *EncodeChannels)->bool
    {
        let pixelCount = cast(u64) image.width * image.height
        pixels.resize(pixelCount)
        let destination = cast([*] u32) notnull pixels.buffer
        let source      = cast(const [*] u8) notnull image.pixels.buffer
        var hasAlpha    = false
        var output: u64

        for [y] in image.height
        {
            var pixel = source + cast(u64) (image.height - y - 1) * image.width8
            for image.width
            {
                var red, green, blue, alpha: u8
                switch image.pf
                {
                case .BGR8:
                    red   = pixel[2]
                    green = pixel[1]
                    blue  = pixel[0]
                    alpha = 0xFF

                case .BGRA8:
                    red   = pixel[2]
                    green = pixel[1]
                    blue  = pixel[0]
                    alpha = pixel[3]

                case .RGB8:
                    red   = pixel[0]
                    green = pixel[1]
                    blue  = pixel[2]
                    alpha = 0xFF

                case .RGBA8:
                    red   = pixel[0]
                    green = pixel[1]
                    blue  = pixel[2]
                    alpha = pixel[3]
                }

                destination[output] = cast(u32) red | (cast(u32) green << 8) |
                                      (cast(u32) blue << 16) | (cast(u32) alpha << 24)
                channels.red.add(red)
                channels.blue.add(blue)
                channels.alpha.add(alpha)
                hasAlpha = hasAlpha or alpha != 0xFF
                output   += 1
                pixel    += image.bpp8
            }
        }

        return hasAlpha
    }

    func writeComplexTreeHeader(writer: *EncodeBitWriter, includeNine: bool)
    {
        writer.writeBits(0, 1)
        let codeCount = includeNine ? 13'u32 : 12'u32
        writer.writeBits(codeCount - 4, 4)
        for [i] in codeCount
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
        if symbol < WEBP_ENCODE_GREEN_SHORT_SYMBOLS
        {
            writer.writeHuffman(symbol, 8)
            return
        }

        let code = WEBP_ENCODE_GREEN_LONG_CODE_BASE + symbol - WEBP_ENCODE_GREEN_SHORT_SYMBOLS
        writer.writeHuffman(code, 9)
    }

    func writeByteSymbol(writer: *EncodeBitWriter, channel: EncodeChannel, value: u8)
    {
        if channel.count == 1 do
            return
        if channel.count == 2
        {
            writer.writeHuffman(value == channel.values[1] ? 1 : 0, 1)
            return
        }

        writer.writeHuffman(value, 8)
    }

    func writeLength(writer: *EncodeBitWriter, length: u32)
    {
        Debug.assert(length >= 1 and length <= 4096)
        for [symbol] in LOSSLESS_LENGTH_CODES
        {
            var base:      u32
            var extraBits: u32
            if symbol < 4
            {
                base = cast(u32) symbol + 1
            }
            else
            {
                extraBits = (cast(u32) symbol - 2) >> 1
                base      = (2 + (cast(u32) symbol & 1)) << extraBits
                base      += 1
            }

            let last = base + (extraBits ? (1'u32 << extraBits) - 1 : 0)
            if length < base or length > last do
                continue

            writeGreenSymbol(writer, LOSSLESS_LITERAL_CODES + cast(u32) symbol)
            if extraBits do
                writer.writeBits(length - base, extraBits)
            return
        }

        Debug.assert(false)
    }

    func writePixels(writer: *EncodeBitWriter, pixels: Array'u32, channels: EncodeChannels)
    {
        let data = cast(const [*] u32) notnull pixels.buffer
        var index: u64
        while index < pixels.count
        {
            if index and data[index] == data[index - 1]
            {
                var length = 1'u32
                while length < 4096 and index + length < pixels.count and data[index + length] == data[index - 1] do
                    length += 1
                writeLength(writer, length)
                index += length
                continue
            }

            let pixel = data[index]
            let red   = cast(u8) (pixel & 0xFF)
            let green = cast(u8) ((pixel >> 8) & 0xFF)
            let blue  = cast(u8) ((pixel >> 16) & 0xFF)
            let alpha = cast(u8) (pixel >> 24)
            writeGreenSymbol(writer, green)
            writeByteSymbol(writer, channels.red, red)
            writeByteSymbol(writer, channels.blue, blue)
            writeByteSymbol(writer, channels.alpha, alpha)
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
        writer.writeBits(cast(u32) image.width - 1, 14)
        writer.writeBits(cast(u32) image.height - 1, 14)
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

public impl IImageEncoder for Encoder
{
    mtd impl canEncode(fileName: string)->bool
    {
        return Path.getExtensionLowerCase(fileName) == ".webp"
    }

    mtd impl encode(result: *ConcatBuffer, image: Image, options: #null any) fail
    {
        if image.width <= 0 or image.height <= 0 or !image.pixels.buffer do
            fail InvalidFormatError{"WebP encoder needs a non-empty image"}
        if image.width > WEBP_ENCODE_MAX_DIMENSION or image.height > WEBP_ENCODE_MAX_DIMENSION do
            fail UnsupportedFormatError{"WebP lossless dimensions cannot exceed 16384 pixels"}

        let expectedBytes = cast(u64) image.width * image.height * image.bpp8
        if image.pixels.count < expectedBytes do
            fail InvalidFormatError{"WebP image pixel buffer ends before its declared dimensions"}

        let payload    = Encoder.encodeLossless(image)
        let paddedSize = payload.count + (payload.count & 1)
        if paddedSize > Swag.U32.Max - 12 do
            fail UnsupportedFormatError{"WebP encoded data does not fit in a RIFF chunk"}

        result.addBytes("RIFF")
        Encoder.writeU32(result, cast(u32) (4 + 8 + paddedSize))
        result.addBytes("WEBP")
        result.addBytes("VP8L")
        Encoder.writeU32(result, cast(u32) payload.count)
        result.addBytes(payload.toSlice())
        if payload.count & 1 do
            result.addNative(0'u8)
    }
}
