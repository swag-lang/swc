//! Format: OpenEXR scanline decoder.
//! Supported: Single-part and multipart RGB, RGBA, or Y scanline images with half/float channels and
//!            no compression, ZIPS, or ZIP lossless compression.
//! Not supported: Tiled, deep, subsampled, UINT, PIZ/PXR24/B44/DWA/HTJ2K data,
//!                or layered channel names.
//! Role: This file reconstructs high-dynamic-range channels into half/full-float Pixel images.
//
#global namespace Exr

using Core, Core.Errors, Core.Math

const Magic = 20000630'u32

struct Channel
{
    name:      String
    pixelType: u32
}

internal struct Decoder { bytes: const [..] u8?; parts: Array'Part; multipart: bool }

#[Swag.Inline]
func readU16(source: const [*] u8)->u16 => cast(u16, source[0]) | (cast(u16, source[1]) << 8)

#[Swag.Inline]
func readU32(source: const [*] u8)->u32 => cast(u32, readU16(source)) | (cast(u32, readU16(source + 2)) << 16)

#[Swag.Inline]
func readU64(source: const [*] u8)->u64 => cast(u64, readU32(source)) | (cast(u64, readU32(source + 4)) << 32)

#[Swag.Inline]
func readF32(source: const [*] u8)->f32 => cast #bit (f32, readU32(source))

func readText(buffer: const [..] u8, offset: *u64, maxLength: u64)->String fail
{
    let start = offset[]
    while offset[] < buffer.count and buffer[offset[]] and offset[] - start <= maxLength do
        offset[] += 1
    if offset[] >= buffer.count or offset[] - start > maxLength do
        fail InvalidFormatError{"OpenEXR header string is not terminated"}
    let result = String.from(cast(string, Swag.makeSlice(buffer.buffer + start, offset[] - start)))
    offset[] += 1
    return result
}

func parseChannels(payload: const [..] u8)->Array'Channel fail
{
    var result: #returntype
    var offset = 0'u64
    while offset < payload.count and payload[offset]
    {
        let name = #move try readText(payload, &offset, 255)
        if offset + 16 > payload.count do
            fail InvalidFormatError{"OpenEXR channel entry is truncated"}
        let pixelType = readU32(payload.buffer + offset)
        let xSampling = readU32(payload.buffer + offset + 8)
        let ySampling = readU32(payload.buffer + offset + 12)
        if pixelType != 1 and pixelType != 2 do
            fail UnsupportedFormatError{"OpenEXR UINT channels are not supported"}
        if xSampling != 1 or ySampling != 1 do
            fail UnsupportedFormatError{"OpenEXR subsampled channels are not supported"}
        for &channel in result
        {
            if channel.name.toString() == name.toString() do
                fail InvalidFormatError{"OpenEXR channel name is duplicated"}
        }

        var channel: Channel
        channel.name      = #move name
        channel.pixelType = pixelType
        result.add(#move channel)
        offset += 16
    }

    if offset >= payload.count or payload[offset] != 0 do
        fail InvalidFormatError{"OpenEXR channel list is not terminated"}
    return result
}

func undoZipPredictor(data: [..] u8, reordered: *Array'u8)
{
    reordered.grow(data.count)
    reordered.count = data.count
    if not data.count do
        return

    // The predictor runs across the two byte planes in file order. Removing 128 from
    // each difference after the first is equivalent to flipping the sign bit at odd offsets.
    const Zero = Simd.splat(0'u8)
    const Bias = cast(Simd.U8x16, [0'u8, 128, 0, 128, 0, 128, 0, 128, 0, 128, 0, 128, 0, 128, 0, 128])
    var carry  = 0'u8
    var offset = 0'u64
    while data.count - offset >= 16
    {
        var values = Simd.load(data.buffer + offset)
        values += Simd.align(Zero, values, 15)
        values += Simd.align(Zero, values, 14)
        values += Simd.align(Zero, values, 12)
        values += Simd.align(Zero, values, 8)
        values += Simd.splat(carry)
        carry  = values[15]
        Simd.store(data.buffer + offset, values ^ Bias)
        offset += 16
    }

    while offset < data.count
    {
        carry        += #wrap data[offset]
        data[offset] = carry ^ (offset & 1 ? 128 : 0)
        offset       += 1
    }

    // Interleave the restored byte planes without reading beyond the last complete pair.
    let pairs = data.count / 2
    let high  = data.buffer + data.count - pairs
    offset = 0
    while pairs - offset >= 16
    {
        let lowBytes  = Simd.load(data.buffer + offset)
        let highBytes = Simd.load(high + offset)
        let target    = reordered.storage() + offset * 2
        Simd.store(target, Simd.interleaveLow(lowBytes, highBytes))
        Simd.store(target + 16, Simd.interleaveHigh(lowBytes, highBytes))
        offset += 16
    }

    while offset < pairs
    {
        reordered[offset * 2]     = data[offset]
        reordered[offset * 2 + 1] = high[offset]
        offset += 1
    }

    if data.count & 1 do
        reordered[offset * 2] = data[offset]
}

func channelComponent(name: string)->s32
{
    switch name
    {
    case "R": return 0
    case "G": return 1
    case "B": return 2
    case "A": return 3
    case "Y": return 4
    }

    return -1
}

#[Swag.Inline]
func canonicalHalf(value: u16)->u16 => (value & 0x7FFF) > 0x7C00 ? (value & 0x8000) | 0x7E00 : value

#[Swag.Inline]
func loadCanonicalHalves(source: const [*] u8)->Simd.U16x8
{
    const Infinity = Simd.splat(0x7C00's16)
    let values    = cast #bit(Simd.U16x8, Simd.load(source))
    let magnitude = cast #bit(Simd.S16x8, values & 0x7FFF'u16)
    return Simd.select(magnitude > Infinity, (values & 0x8000'u16) | 0x7E00'u16, values)
}

// Place the samples for one channel in one of the three adjacent RGB output vectors.
#[Swag.ConstExpr]
func rgbShuffle(sampleBytes, channel, block: u64)->Simd.U8x16
{
    var table: [16] u8
    for index in table.count
    {
        let component = (block * 16 + index) / sampleBytes
        let pixel     = component / 3
        table[index] = component % 3 == channel ? cast(u8, pixel * sampleBytes + index % sampleBytes) : 0x80
    }

    return cast(Simd.U8x16, table)
}

#[Swag.Inline]
func(T) loadColorSamples(source: const [*] u8)->Simd.U8x16
{
    #static if T == u16 do
        return cast #bit(Simd.U8x16, loadCanonicalHalves(source))
    else do
        return Simd.load(source)
}

#[Swag.Inline]
func(T) readColorSample(source: const [*] u8)->T
{
    #static if T == u16 do
        return canonicalHalf(readU16(source))
    else do
        return readU32(source)
}

#[Swag.Inline]
func(T, Pair) storeRgbaSamples(target: [*] u8, r, g, b, a: Simd.U8x16)
{
    let red    = cast #bit(T, r)
    let green  = cast #bit(T, g)
    let blue   = cast #bit(T, b)
    let alpha  = cast #bit(T, a)
    let rgLow  = cast #bit(Pair, Simd.interleaveLow(red, green))
    let rgHigh = cast #bit(Pair, Simd.interleaveHigh(red, green))
    let baLow  = cast #bit(Pair, Simd.interleaveLow(blue, alpha))
    let baHigh = cast #bit(Pair, Simd.interleaveHigh(blue, alpha))
    Simd.store(target, cast #bit(Simd.U8x16, Simd.interleaveLow(rgLow, baLow)))
    Simd.store(target + 16, cast #bit(Simd.U8x16, Simd.interleaveHigh(rgLow, baLow)))
    Simd.store(target + 32, cast #bit(Simd.U8x16, Simd.interleaveLow(rgHigh, baHigh)))
    Simd.store(target + 48, cast #bit(Simd.U8x16, Simd.interleaveHigh(rgHigh, baHigh)))
}

func(T, ALPHA: bool) writePackedColorRow(source: const [*] u8, offsets: [4] u64, target: [*] u8, width: u64)
{
    const SampleBytes = #sizeof(T)
    const BlockPixels = 16 / SampleBytes
    const Stride      = SampleBytes * (ALPHA ? 4 : 3)
    let red   = source + offsets[0]
    let green = source + offsets[1]
    let blue  = source + offsets[2]

    var x: u64
    while width - x >= BlockPixels
    {
        let dst    = target + x * Stride
        let offset = x * SampleBytes
        let r      = loadColorSamples'T(red + offset)
        let g      = loadColorSamples'T(green + offset)
        let b      = loadColorSamples'T(blue + offset)
        #static if ALPHA
        {
            let a = loadColorSamples'T(source + offsets[3] + offset)
            #static if T == u16 do
                storeRgbaSamples'(Simd.U16x8, Simd.U32x4)(dst, r, g, b, a)
            else do
                storeRgbaSamples'(Simd.U32x4, Simd.U64x2)(dst, r, g, b, a)
        }
        else
        {
            const RgbR0 = rgbShuffle(SampleBytes, 0, 0)
            const RgbG0 = rgbShuffle(SampleBytes, 1, 0)
            const RgbB0 = rgbShuffle(SampleBytes, 2, 0)
            const RgbR1 = rgbShuffle(SampleBytes, 0, 1)
            const RgbG1 = rgbShuffle(SampleBytes, 1, 1)
            const RgbB1 = rgbShuffle(SampleBytes, 2, 1)
            const RgbR2 = rgbShuffle(SampleBytes, 0, 2)
            const RgbG2 = rgbShuffle(SampleBytes, 1, 2)
            const RgbB2 = rgbShuffle(SampleBytes, 2, 2)
            Simd.store(dst, Simd.shuffle(r, RgbR0) | Simd.shuffle(g, RgbG0) | Simd.shuffle(b, RgbB0))
            Simd.store(dst + 16, Simd.shuffle(r, RgbR1) | Simd.shuffle(g, RgbG1) | Simd.shuffle(b, RgbB1))
            Simd.store(dst + 32, Simd.shuffle(r, RgbR2) | Simd.shuffle(g, RgbG2) | Simd.shuffle(b, RgbB2))
        }

        x += BlockPixels
    }

    while x < width
    {
        let dst    = cast([*] T, target + x * Stride)
        let offset = x * SampleBytes
        dst[0] = readColorSample'T(red + offset)
        dst[1] = readColorSample'T(green + offset)
        dst[2] = readColorSample'T(blue + offset)
        #static if ALPHA do
            dst[3] = readColorSample'T(source + offsets[3] + offset)
        x += 1
    }
}

func(T) writePackedColorChunk(image: *Image, offsets: [4] u64, source: const [..] u8, firstRow, rowCount: s32)
{
    let width    = cast(u64, image.width)
    let rowBytes = cast(u64, image.rowStride)
    let hasAlpha = image.bytesPerPixel == 4 * #sizeof(T)
    for row in rowCount
    {
        let targetY = image.height - firstRow - row - 1
        let target  = image.pixels.storage() + cast(u64, targetY) * rowBytes
        let input   = source.buffer + cast(u64, row) * rowBytes
        if hasAlpha do
            writePackedColorRow'(T, true)(input, offsets, target, width)
        else do
            writePackedColorRow'(T, false)(input, offsets, target, width)
    }
}

func writeFloatColorChunk(image: *Image, channels: const [..] Channel, source: const [..] u8, firstRow, rowCount: s32)
{
    let components = cast(u64, image.pixelFormat.channels())
    var offset     = 0'u64
    for row in rowCount
    {
        let targetY   = image.height - firstRow - row - 1
        let targetRow = image.pixels.storage() + cast(u64, targetY) * image.rowStride
        for channel in channels
        {
            let input       = source.buffer + offset
            let halfInput   = channel.pixelType == 1
            var targetIndex = cast(u64, channelComponent(channel.name))
            offset += cast(u64, image.width) * (halfInput ? 2 : 4)

            if halfInput
            {
                let target = cast([*] f32, targetRow)
                for x in image.width
                {
                    target[targetIndex] = halfToFloat(readU16(input + cast(u64, x) * 2))
                    targetIndex         += components
                }
            }
            else
            {
                let target = cast([*] u32, targetRow)
                for x in image.width
                {
                    target[targetIndex] = readU32(input + cast(u64, x) * 4)
                    targetIndex         += components
                }
            }
        }
    }
}

func writeGrayscaleChunk(image: *Image, channels: const [..] Channel, source: const [..] u8, firstY, rowCount, yMin: s32) fail
{
    var offset = 0'u64
    for row in rowCount
    {
        let fileY   = firstY + row
        let targetY = image.height - (fileY - yMin) - 1
        if targetY < 0 or targetY >= image.height do
            fail InvalidFormatError{"OpenEXR scanline lies outside the data window"}
        for &channel in channels
        {
            let bytes        = channel.pixelType == 1 ? 2'u64 : 4'u64
            let channelBytes = cast(u64, image.width) * bytes
            if channelBytes > source.count - offset do
                fail InvalidFormatError{"OpenEXR channel pixels are truncated"}
            let component = channelComponent(channel.name.toString())
            if component >= 0
            {
                for x in image.width
                {
                    let input  = source.buffer + offset + cast(u64, x) * bytes
                    let value  = channel.pixelType == 1 ? halfToFloat(readU16(input)) : readF32(input)
                    let target = image.pixels.storage() + cast(u64, targetY) * image.rowStride + cast(u64, x) * image.bytesPerPixel
                    var pixel  = readPixelValue(target, image.pixelFormat)
                    switch component
                    {
                    case 0:
                        pixel.r = value

                    case 1:
                        pixel.g = value

                    case 2:
                        pixel.b = value

                    case 3:
                        pixel.a = value

                    case 4:
                        pixel.r = value
                        pixel.g = value
                        pixel.b = value
                    }

                    writePixelValue(target, image.pixelFormat, pixel)
                }
            }

            offset += channelBytes
        }
    }

    if offset != source.count do
        fail InvalidFormatError{"OpenEXR chunk has bytes after its channel data"}
}

struct Part
{
    channels:    Array'Channel
    compression: u8
    info:        ImageFrameInfo
    yMin:        s32
    rowBytes:    u64
    chunkCount:  u64
    tableOffset: u64
}

impl Part
{
    func parse(buffer: const [..] u8, offset: *u64, multipart: bool, options: DecodeOptions)->Part fail
    {
        var result: #returntype
        result.compression = 255
        var xMin, yMin, xMax, yMax: s32
        var hasDataWindow = false
        var declaredChunks:         u32
        var hasChunkCount = false
        var partType:               String
        while offset[] < buffer.count and buffer[offset[]]
        {
            let name = try readText(buffer, offset, 255)
            let type = try readText(buffer, offset, 255)
            if offset[] + 4 > buffer.count do
                fail InvalidFormatError{"OpenEXR attribute size is truncated"}
            let size = cast(u64, readU32(buffer.buffer + offset[]))
            offset[] += 4
            if size > buffer.count - offset[] do
                fail InvalidFormatError{"OpenEXR attribute exceeds the file"}
            let payload = buffer[offset[] until offset[] + size]
            if name.toString() == "channels" and type.toString() == "chlist"
            {
                result.channels = try parseChannels(payload)
            }
            elif name.toString() == "compression" and type.toString() == "compression"
            {
                if size != 1 do
                    fail InvalidFormatError{"OpenEXR compression attribute has an invalid size"}
                result.compression = payload[0]
            }
            elif name.toString() == "dataWindow" and type.toString() == "box2i"
            {
                if size != 16 do
                    fail InvalidFormatError{"OpenEXR data window has an invalid size"}
                xMin = cast #bit(s32, readU32(payload.buffer))
                yMin = cast #bit(s32, readU32(payload.buffer + 4))
                xMax = cast #bit(s32, readU32(payload.buffer + 8))
                yMax = cast #bit(s32, readU32(payload.buffer + 12))
                hasDataWindow = true
            }
            elif name.toString() == "chunkCount" and type.toString() == "int"
            {
                if size != 4 do
                    fail InvalidFormatError{"OpenEXR chunk count has an invalid size"}
                declaredChunks = readU32(payload.buffer)
                hasChunkCount  = true
            }
            elif name.toString() == "name" and type.toString() == "string"
            {
                result.info.name = cast(string, payload)
            }
            elif name.toString() == "type" and type.toString() == "string"
            {
                partType = cast(string, payload)
            }

            offset[] += size
        }

        if offset[] >= buffer.count do
            fail InvalidFormatError{"OpenEXR header is not terminated"}
        offset[] += 1
        if not result.channels.count or not hasDataWindow or result.compression == 255 do
            fail InvalidFormatError{"OpenEXR required attributes are missing"}
        if multipart and (not hasChunkCount or not result.info.name.count or partType.toString() != "scanlineimage") do
            fail UnsupportedFormatError{"OpenEXR parts require a name, chunk count, and scanline image type"}
        if result.compression != 0 and result.compression != 2 and result.compression != 3 do
            fail UnsupportedFormatError{"OpenEXR compression is not NONE, ZIPS, or ZIP"}
        let width  = cast(s64, xMax) - xMin + 1
        let height = cast(s64, yMax) - yMin + 1
        if width <= 0 or height <= 0 or width > Swag.S32.Max or height > Swag.S32.Max do
            fail InvalidFormatError{"OpenEXR data window dimensions are invalid"}
        var hasR, hasG, hasB, hasY, hasAlpha, hasFloat: bool
        for channel in result.channels
        {
            switch channel.name.toString()
            {
            case "R": hasR = true
            case "G": hasG = true
            case "B": hasB = true
            case "Y": hasY = true
            case "A": hasAlpha = true
            default:  fail UnsupportedFormatError{"OpenEXR layered or auxiliary channels are not supported"}
            }

            hasFloat        = hasFloat or channel.pixelType == 2
            result.rowBytes += cast(u64, width) * (channel.pixelType == 1 ? 2 : 4)
        }

        if not (hasY or (hasR and hasG and hasB)) do
            fail UnsupportedFormatError{"OpenEXR image has neither Y nor RGB color channels"}
        if hasY and hasR and hasG and hasB do
            fail UnsupportedFormatError{"OpenEXR images with both Y and RGB channels are not supported"}
        let grayscale = hasY and not (hasR and hasG and hasB)
        var format: PixelFormat
        if hasFloat
        {
            if grayscale
            {
                format = hasAlpha ? .GrayAlphaF32 : .GrayF32
            }
            else
            {
                format = hasAlpha ? .RGBAF32 : .RGBF32
            }
        }
        else
        {
            if grayscale
            {
                format = hasAlpha ? .GrayAlphaF16 : .GrayF16
            }
            else
            {
                format = hasAlpha ? .RGBAF16 : .RGBF16
            }
        }

        result.info.kind        = multipart ? .Page : .Still
        result.info.width       = cast(s32, width)
        result.info.height      = cast(s32, height)
        result.info.x           = xMin
        result.info.y           = yMin
        result.info.pixelFormat = format
        result.yMin             = yMin
        try options.checkImage(result.info.width, result.info.height, format)
        let linesPerChunk = result.compression == 3 ? 16'u64 : 1'u64
        result.chunkCount = (cast(u64, height) + linesPerChunk - 1) / linesPerChunk
        if hasChunkCount and declaredChunks != result.chunkCount do
            fail InvalidFormatError{"OpenEXR chunk count disagrees with the data window"}
        return result
    }

    mtd decode(buffer: const [..] u8, index: u32, multipart: bool, options: DecodeOptions)->Image fail
    {
        var result: #returntype
        result.init(.info.width, .info.height, .info.pixelFormat)
        if not options.decodePixels do
            return result
        result.allocPixels()
        let grayscale = result.pixelFormat.isGrayscale()
        let halfColor = result.pixelFormat == .RGBF16 or result.pixelFormat == .RGBAF16

        // Validated RGB(A) channels write every component, and chunk validation covers every row.
        if grayscale do
            result.fill(Argb.Black)

        // Each scanline repeats the same channel planes in file order.
        var channelOffsets: [4] u64
        var floatColor = not grayscale and not halfColor
        if halfColor
        {
            let planeBytes = cast(u64, result.width) * 2
            for channel, position in .channels do
                channelOffsets[cast(u64, channelComponent(channel.name))] = position * planeBytes
        }
        elif floatColor
        {
            let planeBytes = cast(u64, result.width) * 4
            for channel, position in .channels
            {
                if channel.pixelType == 1
                {
                    floatColor = false
                    break
                }

                channelOffsets[cast(u64, channelComponent(channel.name))] = position * planeBytes
            }
        }

        let linesPerChunk = .compression == 3 ? 16'u64 : 1'u64
        var seenRows: Array'bool
        seenRows.resize(cast(u64, .info.height))
        var reordered: Array'u8
        for chunkIndex in .chunkCount
        {
            var chunkOffset = readU64(buffer.buffer + .tableOffset + chunkIndex * 8)
            let headerSize  = multipart ? 12'u64 : 8'u64
            if chunkOffset > buffer.count or headerSize > buffer.count - chunkOffset do
                fail InvalidFormatError{"OpenEXR chunk offset points outside the file"}
            if multipart
            {
                if readU32(buffer.buffer + chunkOffset) != index do
                    fail InvalidFormatError{"OpenEXR chunk belongs to another part"}
                chunkOffset += 4
            }

            let firstY     = cast #bit(s32, readU32(buffer.buffer + chunkOffset))
            let packedSize = cast(u64, readU32(buffer.buffer + chunkOffset + 4))
            if packedSize > buffer.count - chunkOffset - 8 do
                fail InvalidFormatError{"OpenEXR chunk is truncated"}
            let relativeY = cast(s64, firstY) - .yMin
            if relativeY < 0 or relativeY >= .info.height or cast(u64, relativeY) % linesPerChunk do
                fail InvalidFormatError{"OpenEXR chunk starts outside its scanline block"}
            let rows = Math.min(cast(s32, linesPerChunk), .info.height - cast(s32, relativeY))
            for row in rows
            {
                let y = cast(u64, relativeY) + cast(u64, row)
                if seenRows[y] do
                    fail InvalidFormatError{"OpenEXR scanline occurs more than once"}
                seenRows[y] = true
            }

            let expected = .rowBytes * cast(u64, rows)
            if options.maxDecodedBytes and expected > options.maxDecodedBytes do
                fail UnsupportedFormatError{"OpenEXR chunk exceeds the decoded byte limit"}
            var pixels = buffer[chunkOffset + 8 until chunkOffset + 8 + packedSize]

            // OpenEXR writes the original bytes when ZIP cannot make the block smaller.
            if .compression and packedSize < expected
            {
                var zlib: Compress.ZLib
                var unpacked = try zlib.decompress(pixels, expected)
                if unpacked.count != expected do
                    fail InvalidFormatError{"OpenEXR ZIP chunk has an invalid decoded size"}
                undoZipPredictor(unpacked.toSlice(), &reordered)
                pixels = reordered.toSlice()
            }

            if pixels.count != expected do
                fail InvalidFormatError{"OpenEXR scanline chunk has an invalid size"}
            if grayscale
            {
                try writeGrayscaleChunk(&result, .channels.toSlice(), pixels, firstY, rows, .yMin)
            }
            elif halfColor
            {
                writePackedColorChunk'u16(&result, channelOffsets, pixels, cast(s32, relativeY), rows)
            }
            elif floatColor
            {
                writePackedColorChunk'u32(&result, channelOffsets, pixels, cast(s32, relativeY), rows)
            }
            else
            {
                writeFloatColorChunk(&result, .channels.toSlice(), pixels, cast(s32, relativeY), rows)
            }
        }

        return result
    }
}

impl IImageSetDecoder for Decoder
{
    mtd impl open(buffer: const [..] u8, options: DecodeOptions)->ImageSetInfo fail
    {
        if buffer.count < 9 or readU32(buffer.buffer) != Magic do
            fail InvalidFormatError{"OpenEXR signature or header is truncated"}
        let version = readU32(buffer.buffer + 4)
        if (version & 0xFF) != 2 do
            fail UnsupportedFormatError{"OpenEXR file version is not 2"}
        if version & 0xA00 do
            fail UnsupportedFormatError{"tiled and deep OpenEXR images are not supported"}
        .multipart = (version & 0x1000) != 0
        .bytes     = buffer
        .parts.clear()
        var offset = 8'u64
        var result: #returntype
        for
        {
            try options.checkFrameCount(.parts.count + 1)
            var part = try Part.parse(buffer, &offset, .multipart, options)
            result.frames.add(part.info)
            .parts.add(#move part)
            if not .multipart do
                break
            if offset >= buffer.count do
                fail InvalidFormatError{"OpenEXR part headers are not terminated"}
            if not buffer[offset]
            {
                offset += 1
                break
            }
        }

        for &part in .parts
        {
            if part.chunkCount > (buffer.count - offset) / 8 do
                fail InvalidFormatError{"OpenEXR chunk offset table is truncated"}
            part.tableOffset = offset
            offset += part.chunkCount * 8
        }

        return result
    }

    mtd impl readFrame(index: u32, options: DecodeOptions)->Image fail
    {
        if index >= .parts.count do
            fail InvalidFormatError{"OpenEXR part index is out of range"}
        return try .parts[index].decode(unwrap .bytes, index, .multipart, options)
    }
}

impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"EXR - OpenEXR", ".exr"}

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        let multiple: IImageSetDecoder = me
        discard try multiple.open(buffer, options)
        return try multiple.readFrame(0, options)
    }
}
