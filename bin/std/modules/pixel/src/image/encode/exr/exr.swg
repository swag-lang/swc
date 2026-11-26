//! Format: OpenEXR scanline encoder.
//! Supported: Single-part, uncompressed Y, YA, RGB, and RGBA scanlines in half or full float.
//! Not supported: Compression, tiles, deep data, multipart files, auxiliary channels, or previews.
//! Role: This file writes fast, lossless HDR interchange from every packed Pixel image.
//
#global namespace Exr

using Core, Core.Errors, Core.Math

internal struct Encoder {}

#[Swag.Inline]
func writeU32(result: *ConcatBuffer, value: u32)
{
    result.addNative(cast(u8, (value & 0xFF)))
    result.addNative(cast(u8, ((value >> 8) & 0xFF)))
    result.addNative(cast(u8, ((value >> 16) & 0xFF)))
    result.addNative(cast(u8, ((value >> 24) & 0xFF)))
}

func writeText(result: *ConcatBuffer, value: string)
{
    result.addBytes(value)
    result.addNative(0'u8)
}

func writeAttribute(result: *ConcatBuffer, name, type: string, payload: const [..] u8)
{
    writeText(result, name)
    writeText(result, type)
    writeU32(result, cast(u32, payload.count))
    result.addBytes(payload)
}

func channelEntry(result: *ConcatBuffer, name: string, pixelType: u32)
{
    writeText(result, name)
    writeU32(result, pixelType)
    writeU32(result, 0)
    writeU32(result, 1)
    writeU32(result, 1)
}

#[Swag.ConstExpr]
private func planeShuffle(sampleBytes, channels, channel, block: u64)->Simd.U8x16
{
    var indices: [16] u8
    for index in indices.count
    {
        let pixel = index / sampleBytes
        let byte  = (pixel * channels + channel) * sampleBytes + index % sampleBytes
        indices[index] = byte / 16 == block ? cast(u8, byte % 16) : 0x80
    }

    return cast(Simd.U8x16, indices)
}

#[Swag.Inline]
private func(SAMPLE_BYTES: u64, CHANNELS: u64, CHANNEL: u64) unpackPlane(first, second, third: Simd.U8x16)->Simd.U8x16
{
    const First  = planeShuffle(SAMPLE_BYTES, CHANNELS, CHANNEL, 0)
    const Second = planeShuffle(SAMPLE_BYTES, CHANNELS, CHANNEL, 1)
    let combined = Simd.shuffle(first, First) | Simd.shuffle(second, Second)
    #static if CHANNELS == 3
    {
        const Third = planeShuffle(SAMPLE_BYTES, CHANNELS, CHANNEL, 2)
        return combined | Simd.shuffle(third, Third)
    }
    else do
        return combined
}

#[Swag.Inline]
private func(T) unpackRgba(destination: [*] u8, planeBytes: u64, source: const [*] u8)
{
    let first  = cast #bit(T, Simd.load(source))
    let second = cast #bit(T, Simd.load(source + 16))
    let third  = cast #bit(T, Simd.load(source + 32))
    let fourth = cast #bit(T, Simd.load(source + 48))
    let low0   = Simd.interleaveLow(first, second)
    let high0  = Simd.interleaveHigh(first, second)
    let low1   = Simd.interleaveLow(third, fourth)
    let high1  = Simd.interleaveHigh(third, fourth)

    var rg0, ba0, rg1, ba1: Simd.U64x2
    #static if T == Simd.U16x8
    {
        rg0 = cast #bit(Simd.U64x2, Simd.interleaveLow(low0, high0))
        ba0 = cast #bit(Simd.U64x2, Simd.interleaveHigh(low0, high0))
        rg1 = cast #bit(Simd.U64x2, Simd.interleaveLow(low1, high1))
        ba1 = cast #bit(Simd.U64x2, Simd.interleaveHigh(low1, high1))
    }
    else
    {
        rg0 = cast #bit(Simd.U64x2, low0)
        ba0 = cast #bit(Simd.U64x2, high0)
        rg1 = cast #bit(Simd.U64x2, low1)
        ba1 = cast #bit(Simd.U64x2, high1)
    }

    Simd.store(destination, cast #bit(Simd.U8x16, Simd.interleaveHigh(ba0, ba1)))
    Simd.store(destination + planeBytes, cast #bit(Simd.U8x16, Simd.interleaveLow(ba0, ba1)))
    Simd.store(destination + 2 * planeBytes, cast #bit(Simd.U8x16, Simd.interleaveHigh(rg0, rg1)))
    Simd.store(destination + 3 * planeBytes, cast #bit(Simd.U8x16, Simd.interleaveLow(rg0, rg1)))
}

#[Swag.Inline]
func(T, CHANNELS: u64) writeScanlinePlanes(destination: [*] u8, source: const [*] u8, width: u64)
{
    const SampleBytes = #sizeof(T)
    #static if CHANNELS == 1 do
        Memory.copy(destination, source, width * SampleBytes)
    else
    {
        const Block = 16 / SampleBytes
        let planeBytes = width * SampleBytes
        var x: u64
        while width - x >= Block
        {
            let input  = source + x * CHANNELS * SampleBytes
            let output = destination + x * SampleBytes
            #static if CHANNELS == 4
            {
                #static if T == u16 do
                    unpackRgba'(Simd.U16x8)(output, planeBytes, input)
                else do
                    unpackRgba'(Simd.U32x4)(output, planeBytes, input)
            }
            else
            {
                let first  = Simd.load(input)
                let second = Simd.load(input + 16)
                let third  = CHANNELS == 3 ? Simd.load(input + 32) : Simd.splat(0'u8)
                Simd.store(output, unpackPlane'(SampleBytes, CHANNELS, CHANNELS - 1)(first, second, third))
                Simd.store(output + planeBytes, unpackPlane'(SampleBytes, CHANNELS, CHANNELS - 2)(first, second, third))
                #static if CHANNELS == 3 do
                    Simd.store(output + 2 * planeBytes, unpackPlane'(SampleBytes, CHANNELS, 0)(first, second, third))
            }

            x += Block
        }

        let packed = cast(const [*] T, source)
        let planes = cast([*] T, destination)
        for tail in x until width
        {
            let pixel = packed + tail * CHANNELS
            planes[tail]         = pixel[CHANNELS - 1]
            planes[width + tail] = pixel[CHANNELS - 2]
            #static if CHANNELS >= 3 do
                planes[2 * width + tail] = pixel[CHANNELS - 3]
            #static if CHANNELS == 4 do
                planes[3 * width + tail] = pixel[0]
        }
    }
}

#[Swag.ConstExpr]
private func makeByteToHalfTable()->[256] u16
{
    var samples: #returntype
    for value in samples.count do
        samples[value] = floatToHalf(cast(f32, value) / 255.0)
    return samples
}

private const ByteToHalf = makeByteToHalfTable()

#[Swag.Inline]
private func(CHANNELS: u64, BLUE_FIRST: bool) writeBytePlanes(destination: [*] u8, source: const [*] u8, width: u64)
{
    const FirstColor = CHANNELS == 4 ? 1'u64 : 0'u64
    const Blue       = BLUE_FIRST ? 0'u64 : 2'u64
    const Red        = 2 - Blue
    let planes = cast([*] u16, destination)
    let colors = planes + FirstColor * width
    for x in width
    {
        let pixel = source + x * CHANNELS
        #static if CHANNELS >= 3
        {
            #static if CHANNELS == 4 do
                planes[x] = ByteToHalf[pixel[3]]
            colors[x]             = ByteToHalf[pixel[Blue]]
            colors[width + x]     = ByteToHalf[pixel[1]]
            colors[2 * width + x] = ByteToHalf[pixel[Red]]
        }
        else
        {
            planes[x] = ByteToHalf[pixel[CHANNELS - 1]]
            #static if CHANNELS == 2 do
                planes[width + x] = ByteToHalf[pixel[0]]
        }
    }
}

func(T, CHANNELS: u64, BYTE_INPUT: bool, BLUE_FIRST: bool) writeScanlines(destination: [*] u8, source: const *Image, fileOffset: u64)
{
    let width      = cast(u64, source.width)
    let rows       = cast(u64, source.height)
    let rowBytes   = width * #sizeof(T) * CHANNELS
    let chunkBytes = rowBytes + 8
    let offsets    = cast([*] u64, destination)
    let tableBytes = 8 * rows
    let chunks     = destination + tableBytes
    let pixels     = source.pixels.storage()
    let stride     = cast(u64, source.rowStride)

    for y in rows
    {
        let chunkOffset = y * chunkBytes
        offsets[y] = Math.nativeToLittleEndian(fileOffset + tableBytes + chunkOffset)
        let chunk  = chunks + chunkOffset
        let header = cast([*] u32, chunk)
        header[0] = Math.nativeToLittleEndian(cast(u32, y))
        header[1] = Math.nativeToLittleEndian(cast(u32, rowBytes))
        let row = pixels + (rows - y - 1) * stride
        #static if BYTE_INPUT do
            writeBytePlanes'(CHANNELS, BLUE_FIRST)(chunk + 8, row, width)
        else do
            writeScanlinePlanes'(T, CHANNELS)(chunk + 8, row, width)
    }
}

func(T) writeChannelLayout(destination: [*] u8, source: const *Image, fileOffset: u64)
{
    switch source.pixelFormat.channels()
    {
    case 1:  writeScanlines'(T, 1, false, false)(destination, source, fileOffset)
    case 2:  writeScanlines'(T, 2, false, false)(destination, source, fileOffset)
    case 3:  writeScanlines'(T, 3, false, false)(destination, source, fileOffset)
    default: writeScanlines'(T, 4, false, false)(destination, source, fileOffset)
    }
}

private func writeByteScanlines(destination: [*] u8, source: const *Image, fileOffset: u64) fail
{
    switch source.pixelFormat
    {
    case .Gray8:      writeScanlines'(u16, 1, true, false)(destination, source, fileOffset)
    case .GrayAlpha8: writeScanlines'(u16, 2, true, false)(destination, source, fileOffset)
    case .RGB8:       writeScanlines'(u16, 3, true, false)(destination, source, fileOffset)
    case .BGR8:       writeScanlines'(u16, 3, true, true)(destination, source, fileOffset)
    case .RGBA8:      writeScanlines'(u16, 4, true, false)(destination, source, fileOffset)
    case .BGRA8:      writeScanlines'(u16, 4, true, true)(destination, source, fileOffset)
    default:          fail InvalidFormatError{"invalid OpenEXR byte source layout"}
    }
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"EXR - OpenEXR", ".exr"}

    mtd impl encode(result: *ConcatBuffer, image: Image, _: any?) fail
    {
        if not image.isValid() or not image.pixelFormat.isPacked() do
            fail InvalidFormatError{"invalid packed image"}

        let grayscale = image.pixelFormat.isGrayscale()
        let fullFloat = image.pixelFormat == .GrayF32 or
                        image.pixelFormat == .GrayAlphaF32 or
                        image.pixelFormat == .RGBF32 or
                        image.pixelFormat == .RGBAF32
        var target: PixelFormat
        if fullFloat
        {
            if grayscale
            {
                target = image.pixelFormat.hasAlpha() ? PixelFormat.GrayAlphaF32 : PixelFormat.GrayF32
            }
            else
            {
                target = image.pixelFormat.hasAlpha() ? PixelFormat.RGBAF32 : PixelFormat.RGBF32
            }
        }
        else
        {
            if grayscale
            {
                target = image.pixelFormat.hasAlpha() ? PixelFormat.GrayAlphaF16 : PixelFormat.GrayF16
            }
            else
            {
                target = image.pixelFormat.hasAlpha() ? PixelFormat.RGBAF16 : PixelFormat.RGBF16
            }
        }

        let byteInput = image.pixelFormat == .Gray8 or
                        image.pixelFormat == .GrayAlpha8 or
                        image.pixelFormat == .RGB8 or
                        image.pixelFormat == .BGR8 or
                        image.pixelFormat == .RGBA8 or
                        image.pixelFormat == .BGRA8
        var converted: Image
        var source:    const *Image = &image
        if image.pixelFormat != target and not byteInput
        {
            converted = image.convertedTo(target)
            source    = &converted
        }

        let pixelType   = fullFloat ? 2'u32 : 1'u32
        let sampleBytes = pixelType == 2 ? 4'u64 : 2'u64
        const RgbNames:       [3] string = ["B", "G", "R"]
        const RgbaNames:      [4] string = ["A", "B", "G", "R"]
        const GrayNames:      [1] string = ["Y"]
        const GrayAlphaNames: [2] string = ["A", "Y"]
        var names: const [..] string
        if grayscale do
            names = source.pixelFormat.hasAlpha() ? GrayAlphaNames : GrayNames
        else do
            names = source.pixelFormat.hasAlpha() ? RgbaNames : RgbNames

        let rowBytes = cast(u64, source.width) * sampleBytes * names.count
        if rowBytes > Swag.U32.Max do
            fail InvalidFormatError{"OpenEXR scanline exceeds its packed size field"}
        let scanlineBytes = cast(u64, source.height) * (rowBytes + 16)

        // Leave room for the fixed attributes and the complete scanline data in one bucket.
        if not result.count() do
            result.grow(512 + scanlineBytes)

        writeU32(result, Magic)
        writeU32(result, 2)
        var channels: ConcatBuffer
        for name in names do
            channelEntry(&channels, name, pixelType)
        channels.addNative(0'u8)
        writeAttribute(result, "channels", "chlist", unwrap channels.toSlice())
        const NoCompression: [1] u8 = [0]
        writeAttribute(result, "compression", "compression", NoCompression)

        var box: ConcatBuffer
        writeU32(&box, 0)
        writeU32(&box, 0)
        writeU32(&box, cast(u32, source.width) - 1)
        writeU32(&box, cast(u32, source.height) - 1)
        writeAttribute(result, "dataWindow", "box2i", unwrap box.toSlice())
        writeAttribute(result, "displayWindow", "box2i", unwrap box.toSlice())
        const IncreasingY: [1] u8 = [0]
        writeAttribute(result, "lineOrder", "lineOrder", IncreasingY)
        const One:   [4] u8 = [0, 0, 0x80, 0x3F]
        const Zero2: [8] u8 = [0, 0, 0, 0, 0, 0, 0, 0]
        writeAttribute(result, "pixelAspectRatio", "float", One)
        writeAttribute(result, "screenWindowCenter", "v2f", Zero2)
        writeAttribute(result, "screenWindowWidth", "float", One)
        result.addNative(0'u8)

        let fileOffset = result.count()
        let scanlines  = result.reserveInPlace(scanlineBytes)
        if byteInput do
            try writeByteScanlines(scanlines, source, fileOffset)
        elif fullFloat do
            writeChannelLayout'u32(scanlines, source, fileOffset)
        else do
            writeChannelLayout'u16(scanlines, source, fileOffset)
    }
}
