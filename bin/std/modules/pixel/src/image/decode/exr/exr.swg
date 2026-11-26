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
    name:      string     // Borrows the encoded channel list.
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

func readText(buffer: const [..] u8, offset: *u64)->string fail
{
    let start = offset[]
    if start >= buffer.count do
        fail InvalidFormatError{"OpenEXR header string is not terminated"}
    let source = buffer.buffer + start
    let limit  = Math.min(buffer.count - start, 256'u64)
    var length: u64
    while length < limit and source[length] do
        length += 1
    if length == limit do
        fail InvalidFormatError{"OpenEXR header string is not terminated"}
    offset[] = start + length + 1
    return cast(string, Swag.makeSlice(source, length))
}

func parseChannels(payload: const [..] u8)->Array'Channel fail
{
    var result: #returntype
    var offset = 0'u64
    while offset < payload.count and payload[offset]
    {
        let name = try readText(payload, &offset)
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
            if channel.name == name do
                fail InvalidFormatError{"OpenEXR channel name is duplicated"}
        }

        var channel: Channel
        channel.name      = name
        channel.pixelType = pixelType
        result.add(channel)
        offset += 16
    }

    if offset >= payload.count or payload[offset] != 0 do
        fail InvalidFormatError{"OpenEXR channel list is not terminated"}
    return result
}

func restoreZipPlanes(data: [..] u8)
{
    // The predictor runs across the two byte planes in file order. Removing 128 from
    // each difference after the first is equivalent to flipping the sign bit at odd offsets.
    const Zero = Simd.splat(0'u8)
    const Bias = cast(Simd.U8x16, [0'u8, 128, 0, 128, 0, 128, 0, 128, 0, 128, 0, 128, 0, 128, 0, 128])
    const Last = Simd.splat(15'u8)
    var carry  = Zero
    var offset = 0'u64
    while data.count - offset >= 16
    {
        var values = Simd.load(data.buffer + offset)
        values += Simd.align(Zero, values, 15)
        values += Simd.align(Zero, values, 14)
        values += Simd.align(Zero, values, 12)
        values += Simd.align(Zero, values, 8)
        let nextCarry = carry + Simd.shuffle(values, Last)
        Simd.store(data.buffer + offset, (values + carry) ^ Bias)
        carry  = nextCarry
        offset += 16
    }

    var tail = carry[0]
    while offset < data.count
    {
        tail         += #wrap data[offset]
        data[offset] = tail ^ (offset & 1 ? 128 : 0)
        offset       += 1
    }
}

func undoZipPredictor(data: [..] u8, reordered: *Array'u8)
{
    reordered.grow(data.count)
    reordered.count = data.count
    if not data.count do
        return
    restoreZipPlanes(data)

    // Interleave the restored byte planes without reading beyond the last complete pair.
    let pairs  = data.count / 2
    let high   = data.buffer + data.count - pairs
    var offset = 0'u64
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
func canonicalHalves(values: Simd.U16x8)->Simd.U16x8
{
    const Infinity = Simd.splat(0x7C00's16)
    let magnitude = cast #bit(Simd.S16x8, values & 0x7FFF'u16)
    return Simd.select(magnitude > Infinity, (values & 0x8000'u16) | 0x7E00'u16, values)
}

#[Swag.Inline]
func loadCanonicalHalves(source: const [*] u8)->Simd.U16x8 => canonicalHalves(cast #bit(Simd.U16x8, Simd.load(source)))

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
                PackedPixel.storeQuads'(Simd.U16x8, Simd.U32x4)(dst, r, g, b, a)
            else do
                PackedPixel.storeQuads'(Simd.U32x4, Simd.U64x2)(dst, r, g, b, a)
        }
        else do
            PackedPixel.storeTriplets'SampleBytes(dst, r, g, b)

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

#[Swag.Inline]
func widenHalfSamples(source: const [*] u8)->Simd.U8x16
{
    var values: u64
    Memory.copy(&values, source, 8)
    let half      = Simd.widenLow(cast #bit(Simd.U16x8, Simd.splat(values)))
    let exponent  = half & 0x7C00'u32
    let mantissa  = (half & 0x03FF'u32) << 13
    let normal    = ((exponent << 13) + 0x3800_0000'u32) | mantissa
    let nonfinite = 0x7F80_0000'u32 | mantissa

    // Subtract 2^-14 from the biased significand to reconstruct subnormals exactly.
    let biased    = cast #bit(Simd.F32x4, 0x3880_0000'u32 | mantissa)
    let subnormal = cast #bit(Simd.U32x4, biased - Simd.splat(1'f32 / 16384.0))
    let finite    = Simd.select(exponent == Simd.splat(0'u32), subnormal, normal)
    let bits      = Simd.select(exponent == Simd.splat(0x7C00'u32), nonfinite, finite)
    return cast #bit(Simd.U8x16, bits | ((half & 0x8000'u32) << 16))
}

#[Swag.Inline]
func loadMixedColorSamples(source: const [*] u8, sampleBytes: u64)->Simd.U8x16
{
    if sampleBytes == 2 do
        return widenHalfSamples(source)
    return Simd.load(source)
}

#[Swag.Inline]
func readMixedColorSample(source: const [*] u8, sampleBytes: u64)->u32
{
    if sampleBytes == 2 do
        return cast #bit(u32, halfToFloat(readU16(source)))
    return readU32(source)
}

func(ALPHA: bool) writeMixedColorRow(source: const [*] u8, offsets, sampleBytes: [4] u64, target: [*] u8, width: u64)
{
    const Stride = ALPHA ? 16'u64 : 12'u64
    let redBytes   = sampleBytes[0]
    let greenBytes = sampleBytes[1]
    let blueBytes  = sampleBytes[2]
    let alphaBytes = sampleBytes[3]
    let redStep    = redBytes * 4
    let greenStep  = greenBytes * 4
    let blueStep   = blueBytes * 4
    let alphaStep  = alphaBytes * 4
    var redInput   = source + offsets[0]
    var greenInput = source + offsets[1]
    var blueInput  = source + offsets[2]
    var alphaInput = source + offsets[3]
    var dst        = target

    var x: u64
    while width - x >= 4
    {
        let r = loadMixedColorSamples(redInput, redBytes)
        let g = loadMixedColorSamples(greenInput, greenBytes)
        let b = loadMixedColorSamples(blueInput, blueBytes)
        #static if ALPHA
        {
            let a = loadMixedColorSamples(alphaInput, alphaBytes)
            PackedPixel.storeQuads'(Simd.U32x4, Simd.U64x2)(dst, r, g, b, a)
            alphaInput += alphaStep
        }
        else do
            PackedPixel.storeTriplets'4(dst, r, g, b)
        redInput   += redStep
        greenInput += greenStep
        blueInput  += blueStep
        dst        += 4 * Stride
        x          += 4
    }

    while x < width
    {
        let values = cast([*] u32, dst)
        values[0] = readMixedColorSample(redInput, redBytes)
        values[1] = readMixedColorSample(greenInput, greenBytes)
        values[2] = readMixedColorSample(blueInput, blueBytes)
        #static if ALPHA
        {
            values[3]  = readMixedColorSample(alphaInput, alphaBytes)
            alphaInput += alphaBytes
        }

        redInput   += redBytes
        greenInput += greenBytes
        blueInput  += blueBytes
        dst        += Stride
        x          += 1
    }
}

func writeMixedColorChunk(image: *Image, offsets: [4] u64, halfChannels: u8, source: const [..] u8, firstRow, rowCount: s32, rowBytes: u64)
{
    let width    = cast(u64, image.width)
    let hasAlpha = image.bytesPerPixel == 16
    var sampleBytes: [4] u64
    for component in 4'u64 do
        sampleBytes[component] = halfChannels & (1'u8 << component) ? 2 : 4

    for row in rowCount
    {
        let targetY = image.height - firstRow - row - 1
        let target  = image.pixels.storage() + cast(u64, targetY) * image.rowStride
        let input   = source.buffer + cast(u64, row) * rowBytes
        if hasAlpha do
            writeMixedColorRow'true(input, offsets, sampleBytes, target, width)
        else do
            writeMixedColorRow'false(input, offsets, sampleBytes, target, width)
    }
}

func(ALPHA: bool) writeGrayHalfRow(source: const [*] u8, target: [*] u8, width: u64, alphaFirst: bool)
{
    const PixelBytes = ALPHA ? 4'u64 : 2'u64
    let planeBytes = width * 2
    let gray       = alphaFirst ? source + planeBytes : source
    let alpha      = alphaFirst ? source : source + planeBytes
    #static if not ALPHA do
        discard alpha
    var x: u64
    while width - x >= 8
    {
        let destination = cast([*] u16, target + x * PixelBytes)
        let luminance   = loadCanonicalHalves(gray + x * 2)
        #static if ALPHA
        {
            let opacity = loadCanonicalHalves(alpha + x * 2)
            Simd.store(destination, Simd.interleaveLow(luminance, opacity))
            Simd.store(destination + 8, Simd.interleaveHigh(luminance, opacity))
        }
        else do
            Simd.store(destination, luminance)
        x += 8
    }

    while x < width
    {
        let destination = cast([*] u16, target + x * PixelBytes)
        destination[0] = canonicalHalf(readU16(gray + x * 2))
        #static if ALPHA do
            destination[1] = canonicalHalf(readU16(alpha + x * 2))
        x += 1
    }
}

func writeGrayZipHalfChunk(image: *Image, source: [..] u8, firstRow, rows: s32)
{
    restoreZipPlanes(source)
    let width       = cast(u64, image.width)
    let planeBytes  = source.count / 2
    let low         = source.buffer
    let high        = low + planeBytes
    let destination = cast([*] u16, image.pixels.storage())
    for row in rows
    {
        let targetY = image.height - firstRow - row - 1
        let target  = destination + cast(u64, targetY) * width
        let src     = cast(u64, row) * width
        var x: u64
        while width - x >= 16
        {
            let lo     = Simd.load(low + src + x)
            let hi     = Simd.load(high + src + x)
            let first  = canonicalHalves(cast #bit(Simd.U16x8, Simd.interleaveLow(lo, hi)))
            let second = canonicalHalves(cast #bit(Simd.U16x8, Simd.interleaveHigh(lo, hi)))
            Simd.store(target + x, first)
            Simd.store(target + x + 8, second)
            x += 16
        }

        while x < width
        {
            target[x] = canonicalHalf(Math.make16(high[src + x], low[src + x]))
            x         += 1
        }
    }
}

func writeGrayHalfChunk(image: *Image, source: const [..] u8, firstRow, rows: s32, alphaFirst: bool)
{
    let width    = cast(u64, image.width)
    let rowBytes = cast(u64, image.rowStride)
    let hasAlpha = image.pixelFormat == .GrayAlphaF16
    for row in rows
    {
        let targetY = image.height - firstRow - row - 1
        let target  = image.pixels.storage() + cast(u64, targetY) * rowBytes
        let input   = source.buffer + cast(u64, row) * rowBytes
        if hasAlpha do
            writeGrayHalfRow'true(input, target, width, alphaFirst)
        else do
            writeGrayHalfRow'false(input, target, width, false)
    }
}

func writeGrayFloatChunk(image: *Image, source: const [..] u8, firstRow, rows: s32, grayBytes, alphaBytes: u64, alphaFirst: bool)
{
    let width       = cast(u64, image.width)
    let sourceBytes = width * (grayBytes + alphaBytes)
    for row in rows
    {
        let targetY = image.height - firstRow - row - 1
        let target  = image.pixels.storage() + cast(u64, targetY) * image.rowStride
        let input   = source.buffer + cast(u64, row) * sourceBytes
        if not alphaBytes
        {
            Memory.copy(target, input, sourceBytes)
            continue
        }

        let gray  = alphaFirst ? input + width * alphaBytes : input
        let alpha = alphaFirst ? input : input + width * grayBytes
        let dst   = cast([*] u32, target)
        var x: u64
        while width - x >= 4
        {
            let luminance = cast #bit(Simd.U32x4, loadMixedColorSamples(gray + x * grayBytes, grayBytes))
            let opacity   = cast #bit(Simd.U32x4, loadMixedColorSamples(alpha + x * alphaBytes, alphaBytes))
            Simd.store(dst + x * 2, Simd.interleaveLow(luminance, opacity))
            Simd.store(dst + x * 2 + 4, Simd.interleaveHigh(luminance, opacity))
            x += 4
        }

        while x < width
        {
            dst[x * 2]     = readMixedColorSample(gray + x * grayBytes, grayBytes)
            dst[x * 2 + 1] = readMixedColorSample(alpha + x * alphaBytes, alphaBytes)
            x += 1
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
            let component = channelComponent(channel.name)
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

struct ScanlineLayout
{
    channelOffsets:        [4] u64
    grayBytes, alphaBytes: u8
    halfChannels:          u8
    grayscale, grayHalf, halfColor, floatColor, alphaFirst: bool
}

struct ScanlineChunk
{
    pixels:   const [..] u8
    firstY, relativeY, rows: s32
    expected: u64
}

struct ScanlineScratch
{
    reordered:    Array'u8
    cachedPixels: const [..] u8?
    cachedFirstRow, cachedRows: s32
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
        var partType      = ""
        while offset[] < buffer.count and buffer[offset[]]
        {
            let name = try readText(buffer, offset)
            let type = try readText(buffer, offset)
            if offset[] + 4 > buffer.count do
                fail InvalidFormatError{"OpenEXR attribute size is truncated"}
            let size = cast(u64, readU32(buffer.buffer + offset[]))
            offset[] += 4
            if size > buffer.count - offset[] do
                fail InvalidFormatError{"OpenEXR attribute exceeds the file"}
            let payload = buffer[offset[] until offset[] + size]
            if name == "channels" and type == "chlist"
            {
                result.channels = try parseChannels(payload)
            }
            elif name == "compression" and type == "compression"
            {
                if size != 1 do
                    fail InvalidFormatError{"OpenEXR compression attribute has an invalid size"}
                result.compression = payload[0]
            }
            elif name == "dataWindow" and type == "box2i"
            {
                if size != 16 do
                    fail InvalidFormatError{"OpenEXR data window has an invalid size"}
                xMin = cast #bit(s32, readU32(payload.buffer))
                yMin = cast #bit(s32, readU32(payload.buffer + 4))
                xMax = cast #bit(s32, readU32(payload.buffer + 8))
                yMax = cast #bit(s32, readU32(payload.buffer + 12))
                hasDataWindow = true
            }
            elif name == "chunkCount" and type == "int"
            {
                if size != 4 do
                    fail InvalidFormatError{"OpenEXR chunk count has an invalid size"}
                declaredChunks = readU32(payload.buffer)
                hasChunkCount  = true
            }
            elif name == "name" and type == "string"
            {
                result.info.name = cast(string, payload)
            }
            elif name == "type" and type == "string"
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
        if multipart and (not hasChunkCount or not result.info.name.count or partType != "scanlineimage") do
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
            switch channel.name
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

    mtd readChunkTable(fileSize, offset: u64)->u64 fail
    {
        if .chunkCount > (fileSize - offset) / 8 do
            fail InvalidFormatError{"OpenEXR chunk offset table is truncated"}
        .tableOffset = offset
        return offset + .chunkCount * 8
    }

    #[Swag.Inline]
    mtd const readScanlineChunk(buffer: const [..] u8, chunkIndex: u64, index: u32, multipart: bool, linesPerChunk: u64, seenRows: [..] bool, maxDecodedBytes: u64)->ScanlineChunk fail
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
        if relativeY < 0 or relativeY >= .info.height or cast(u64, relativeY) & (linesPerChunk - 1) do
            fail InvalidFormatError{"OpenEXR chunk starts outside its scanline block"}
        let start = cast(u64, relativeY)
        if seenRows[start] do
            fail InvalidFormatError{"OpenEXR scanline occurs more than once"}
        seenRows[start] = true
        let rows     = Math.min(cast(s32, linesPerChunk), .info.height - cast(s32, relativeY))
        let expected = .rowBytes * cast(u64, rows)
        if maxDecodedBytes and expected > maxDecodedBytes do
            fail UnsupportedFormatError{"OpenEXR chunk exceeds the decoded byte limit"}
        return {pixels: buffer[chunkOffset + 8 until chunkOffset + 8 + packedSize], firstY, relativeY: cast(s32, relativeY), rows, expected}
    }

    #[Swag.Inline]
    mtd const writeScanlineChunk(image: *Image, chunk: ScanlineChunk, layout: ScanlineLayout, reordered: *Array'u8) fail
    {
        var pixels = chunk.pixels

        // OpenEXR writes the original bytes when ZIP cannot make the block smaller.
        if .compression and pixels.count < chunk.expected
        {
            var zlib: Compress.ZLib
            var unpacked = try zlib.decompress(pixels, chunk.expected, maxOutputSize: chunk.expected)
            if unpacked.count != chunk.expected do
                fail InvalidFormatError{"OpenEXR ZIP chunk has an invalid decoded size"}
            if layout.grayHalf and image.pixelFormat == .GrayF16
            {
                writeGrayZipHalfChunk(image, unpacked.toSlice(), chunk.relativeY, chunk.rows)
                return
            }

            undoZipPredictor(unpacked.toSlice(), reordered)
            pixels = reordered.toSlice()
        }

        if pixels.count != chunk.expected do
            fail InvalidFormatError{"OpenEXR scanline chunk has an invalid size"}
        if layout.grayHalf
        {
            writeGrayHalfChunk(image, pixels, chunk.relativeY, chunk.rows, layout.alphaFirst)
        }
        elif layout.grayscale
        {
            if layout.grayBytes do
                writeGrayFloatChunk(image, pixels, chunk.relativeY, chunk.rows, layout.grayBytes, layout.alphaBytes, layout.alphaFirst)
            else do
                try writeGrayscaleChunk(image, .channels.toSlice(), pixels, chunk.firstY, chunk.rows, .yMin)
        }
        elif layout.halfColor
        {
            writePackedColorChunk'u16(image, layout.channelOffsets, pixels, chunk.relativeY, chunk.rows)
        }
        elif layout.floatColor
        {
            writePackedColorChunk'u32(image, layout.channelOffsets, pixels, chunk.relativeY, chunk.rows)
        }
        else
        {
            writeMixedColorChunk(image, layout.channelOffsets, layout.halfChannels, pixels, chunk.relativeY, chunk.rows, .rowBytes)
        }
    }

    #[Swag.Inline]
    mtd const decodeScanlineChunk(image: *Image, chunk: ScanlineChunk, layout: ScanlineLayout, scratch: *ScanlineScratch) fail
    {
        // Comparing only small packed blocks keeps cache misses cheap.
        let cacheable = .compression and chunk.pixels.count < chunk.expected / 4
        let cached    = scratch.cachedPixels
        if cacheable and
           cached and
           scratch.cachedRows == chunk.rows and
           cached.count == chunk.pixels.count and
           Memory.compare(cached.buffer, chunk.pixels.buffer, chunk.pixels.count) == 0
        {
            let rowBytes = cast(u64, image.rowStride)
            let first    = cast(u64, image.height - chunk.relativeY - chunk.rows) * rowBytes
            let previous = cast(u64, image.height - scratch.cachedFirstRow - chunk.rows) * rowBytes
            let output   = image.pixels.storage()
            Memory.copy(output + first, output + previous, cast(u64, chunk.rows) * rowBytes)
            return
        }

        try .writeScanlineChunk(image, chunk, layout, &scratch.reordered)
        if cacheable
        {
            scratch.cachedPixels   = chunk.pixels
            scratch.cachedFirstRow = chunk.relativeY
            scratch.cachedRows     = chunk.rows
        }
    }

    #[Swag.NoInline]
    mtd const decodeZipBatches(buffer: const [..] u8, index: u32, multipart: bool, linesPerChunk: u64, options: DecodeOptions, image: *Image, layout: const *ScanlineLayout, seenRows: [..] bool) fail
    {
        var chunks: Array'ScanlineChunk
        chunks.reserve(.chunkCount)
        var indexError:      Swag.Error
        var compressedBytes: u64
        for chunkIndex in .chunkCount
        {
            catch
            {
                let chunk = try .readScanlineChunk(buffer, chunkIndex, index, multipart, linesPerChunk, seenRows, options.maxDecodedBytes)
                if chunk.pixels.count < chunk.expected do
                    compressedBytes += chunk.pixels.count
                chunks.add(chunk)
            } as indexError
            if not indexError.isEmpty() do
                break
        }

        let workers = chunks.count >= 2 and compressedBytes >= 512 * 1024 ? Swag.workerCount() : 0
        if workers <= 1
        {
            var scratch: ScanlineScratch = {}
            for chunk in chunks do
                try .decodeScanlineChunk(image, chunk[], layout[], &scratch)
            try indexError.raise()
            return
        }

        // Aligned and unique block starts make worker output rows disjoint. Each batch owns
        // its scratch and records its first error, so failures are reported in file order.
        const MaxBatches = 8'u64
        let batches = Math.min(chunks.count, Math.min(cast(u64, workers) * 2, MaxBatches))
        let part    = me
        let work:   const [..] ScanlineChunk = chunks.toSlice()
        var errors: [MaxBatches] Swag.Error
        parallel for |part, image, layout, work, batches, &errors| batch in batches
        {
            var scratch: ScanlineScratch = {}
            let first = batch * work.count / batches
            let end   = (batch + 1) * work.count / batches
            for chunkIndex in first until end
            {
                catch part.decodeScanlineChunk(image, work[chunkIndex], layout[], &scratch)
                {
                    errors[batch].capture(Swag.err)
                    break
                }
            }
        }

        for batch in batches do
            try errors[batch].raise()
        try indexError.raise()
    }

    mtd decode(buffer: const [..] u8, index: u32, multipart: bool, options: DecodeOptions)->Image fail
    {
        var result: #returntype
        result.init(.info.width, .info.height, .info.pixelFormat)
        if not options.decodePixels do
            return result
        result.allocPixels()
        let grayscale  = result.pixelFormat.isGrayscale()
        let halfColor  = result.pixelFormat == .RGBF16 or result.pixelFormat == .RGBAF16
        let packedGray = grayscale and .channels.count == result.pixelFormat.channels()
        let grayHalf   = packedGray and result.pixelFormat.bitDepth() == 16
        let alphaFirst = packedGray and .channels[0].name == "A"
        var grayBytes, alphaBytes: u8
        if packedGray and not grayHalf
        {
            grayBytes = .channels[alphaFirst ? 1 : 0].pixelType == 1 ? 2 : 4
            if .channels.count == 2 do
                alphaBytes = .channels[alphaFirst ? 0 : 1].pixelType == 1 ? 2 : 4
        }

        // The packed paths write all channels of each validated row.
        if grayscale and not packedGray do
            result.fill(Argb.Black)

        // Each scanline repeats the same channel planes in file order.
        var channelOffsets: [4] u64
        var halfChannels:   u8
        let floatColor = not grayscale and not halfColor and .rowBytes == cast(u64, result.rowStride)
        if halfColor or floatColor
        {
            let planeBytes = cast(u64, result.width) * (halfColor ? 2 : 4)
            for channel, position in .channels do
                channelOffsets[cast(u64, channelComponent(channel.name))] = position * planeBytes
        }
        elif not grayscale
        {
            var offset: u64
            for channel in .channels
            {
                let component = cast(u64, channelComponent(channel.name))
                let bytes     = channel.pixelType == 1 ? 2'u64 : 4'u64
                channelOffsets[component] = offset
                if bytes == 2 do
                    halfChannels |= 1'u8 << component
                offset += cast(u64, result.width) * bytes
            }
        }

        let linesPerChunk = .compression == 3 ? 16'u64 : 1'u64
        var seenRows: Array'bool
        seenRows.resize(cast(u64, .info.height))
        var layout: ScanlineLayout = {channelOffsets, grayBytes, alphaBytes, halfChannels, grayscale, grayHalf, halfColor, floatColor, alphaFirst}

        // A fully stored single part needs a table entry and a scanline header per block.
        // Let the serial path copy these blocks without an auxiliary chunk index.
        if .compression and
           .chunkCount >= 8 and
           buffer.count >= 512 * 1024 and
           result.byteCount >= 1024 * 1024 and
           (multipart or buffer.count < .tableOffset + .chunkCount * 16 + result.byteCount)
        {
            try .decodeZipBatches(buffer, index, multipart, linesPerChunk, options, &result, &layout, seenRows.toSlice())
            return result
        }

        var scratch: ScanlineScratch = {}
        for chunkIndex in .chunkCount
        {
            let chunk = try .readScanlineChunk(buffer, chunkIndex, index, multipart, linesPerChunk, seenRows.toSlice(), options.maxDecodedBytes)
            try .decodeScanlineChunk(&result, chunk, layout, &scratch)
        }

        return result
    }
}

func readVersion(buffer: const [..] u8)->u32 fail
{
    if buffer.count < 9 or readU32(buffer.buffer) != Magic do
        fail InvalidFormatError{"OpenEXR signature or header is truncated"}
    let version = readU32(buffer.buffer + 4)
    if (version & 0xFF) != 2 do
        fail UnsupportedFormatError{"OpenEXR file version is not 2"}
    if version & 0xA00 do
        fail UnsupportedFormatError{"tiled and deep OpenEXR images are not supported"}
    return version
}

impl IImageSetDecoder for Decoder
{
    mtd impl open(buffer: const [..] u8, options: DecodeOptions)->ImageSetInfo fail
    {
        let version = try readVersion(buffer)
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

        for &part in .parts do
            offset = try part.readChunkTable(buffer.count, offset)

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
        let version = try readVersion(buffer)
        if version & 0x1000
        {
            let multiple: IImageSetDecoder = me
            discard try multiple.open(buffer, options)
            return try multiple.readFrame(0, options)
        }

        try options.checkFrameCount(1)
        var offset = 8'u64
        var part   = try Part.parse(buffer, &offset, false, options)
        discard try part.readChunkTable(buffer.count, offset)
        return try part.decode(buffer, 0, false, options)
    }
}
