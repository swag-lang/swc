#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func exrAddU32(result: *ConcatBuffer, value: u32)
{
    result.addNative(cast(u8, (value & 0xFF)))
    result.addNative(cast(u8, ((value >> 8) & 0xFF)))
    result.addNative(cast(u8, ((value >> 16) & 0xFF)))
    result.addNative(cast(u8, ((value >> 24) & 0xFF)))
}

func exrAddU64(result: *ConcatBuffer, value: u64)
{
    exrAddU32(result, cast(u32, (value & 0xFFFF_FFFF)))
    exrAddU32(result, cast(u32, (value >> 32)))
}

func exrAddText(result: *ConcatBuffer, value: string)
{
    result.addBytes(value)
    result.addNative(0'u8)
}

func exrAddAttribute(result: *ConcatBuffer, name, type: string, payload: const [..] u8)
{
    exrAddText(result, name)
    exrAddText(result, type)
    exrAddU32(result, cast(u32, payload.count))
    result.addBytes(payload)
}

func exrInvalidZipFixture()->ConcatBuffer
{
    var channels: ConcatBuffer
    exrAddText(&channels, "Y")
    exrAddU32(&channels, 1)     // HALF channel.
    exrAddU32(&channels, 0)
    exrAddU32(&channels, 1)
    exrAddU32(&channels, 1)
    channels.addNative(0'u8)

    var compression: [1] u8 = [2]     // ZIPS.
    var dataWindow:  ConcatBuffer
    exrAddU32(&dataWindow, 0)
    exrAddU32(&dataWindow, 0)
    exrAddU32(&dataWindow, 3)
    exrAddU32(&dataWindow, 0)

    var header: ConcatBuffer
    exrAddAttribute(&header, "channels", "chlist", unwrap channels.toSlice())
    exrAddAttribute(&header, "compression", "compression", compression)
    exrAddAttribute(&header, "dataWindow", "box2i", unwrap dataWindow.toSlice())
    header.addNative(0'u8)

    var result: ConcatBuffer
    exrAddU32(&result, Exr.Magic)
    exrAddU32(&result, 2)
    result.addBytes(unwrap header.toSlice())
    exrAddU64(&result, result.count() + 8)
    exrAddU32(&result, 0)     // First scanline.
    exrAddU32(&result, 8)     // Same as the decoded 4xHALF row size.
    for 8 do
        result.addNative(0xFF'u8)     // Not a valid ZLIB stream.
    return result
}

func exrMixedRgbYFixture()->ConcatBuffer
{
    var channels: ConcatBuffer
    for name in ["B", "G", "R", "Y"]
    {
        exrAddText(&channels, name)
        exrAddU32(&channels, 1) // HALF channel.
        exrAddU32(&channels, 0)
        exrAddU32(&channels, 1)
        exrAddU32(&channels, 1)
    }
    channels.addNative(0'u8)

    var compression: [1] u8 = [0] // No compression.
    var dataWindow:  ConcatBuffer
    exrAddU32(&dataWindow, 0)
    exrAddU32(&dataWindow, 0)
    exrAddU32(&dataWindow, 0)
    exrAddU32(&dataWindow, 0)

    var header: ConcatBuffer
    exrAddAttribute(&header, "channels", "chlist", unwrap channels.toSlice())
    exrAddAttribute(&header, "compression", "compression", compression)
    exrAddAttribute(&header, "dataWindow", "box2i", unwrap dataWindow.toSlice())
    header.addNative(0'u8)

    var result: ConcatBuffer
    exrAddU32(&result, Exr.Magic)
    exrAddU32(&result, 2)
    result.addBytes(unwrap header.toSlice())
    return result
}

func exrUnalignedFloatFixture()->ConcatBuffer
{
    var channels: ConcatBuffer
    exrAddText(&channels, "Y")
    exrAddU32(&channels, 2) // FLOAT channel.
    exrAddU32(&channels, 0)
    exrAddU32(&channels, 1)
    exrAddU32(&channels, 1)
    channels.addNative(0'u8)

    var compression: [1] u8 = [0] // No compression.
    var dataWindow:  ConcatBuffer
    exrAddU32(&dataWindow, 0)
    exrAddU32(&dataWindow, 0)
    exrAddU32(&dataWindow, 0)
    exrAddU32(&dataWindow, 0)

    var header: ConcatBuffer
    exrAddAttribute(&header, "channels", "chlist", unwrap channels.toSlice())
    exrAddAttribute(&header, "compression", "compression", compression)
    exrAddAttribute(&header, "dataWindow", "box2i", unwrap dataWindow.toSlice())
    header.addNative(0'u8)

    var result: ConcatBuffer
    exrAddU32(&result, Exr.Magic)
    exrAddU32(&result, 2)
    result.addBytes(unwrap header.toSlice())
    let tableEnd   = result.count() + 8
    let chunkOffset = tableEnd + (tableEnd & 1 ? 0 : 1)
    exrAddU64(&result, chunkOffset)
    while result.count() < chunkOffset do
        result.addNative(0'u8)
    exrAddU32(&result, 0)          // First scanline.
    exrAddU32(&result, 4)          // One FLOAT sample.
    exrAddU32(&result, 0x3F800000) // 1.0f, at an odd address.
    return result
}

// A non-null but truncated source buffer is invalid for EXR encoding.
#test
{
    var source = Image.create(1, 1, .RGB8)
    source.pixels.count = 0

    var error: Swag.Error
    discard catch source.encodeToBytes("truncated.exr") as error
    Swag.require(error.value() is Errors.InvalidFormatError)
}

// Error: duplicate EXR channel names are invalid.
#test
{
    var source  = Image.create(1, 1, .RGBAF16)
    var encoded = expect source.encode("duplicate-channel.exr")
    encoded.makeLinear()
    var bytes  = unwrap encoded.toSlice()
    var offset = 8'u64 + 9 + 7 + 4
    var found  = false
    while bytes[offset]
    {
        if bytes[offset] == 'A' and bytes[offset + 1] == 0
        {
            bytes[offset] = 'R'
            found         = true
            break
        }

        while bytes[offset] do
            offset += 1
        offset += 1 + 16
    }

    Swag.require(found)

    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try Image.decode("duplicate-channel.exr", bytes) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

#test
{
    var source  = Image.create(3, 2, .RGBF16)
    let samples = cast([*] u16, source.pixels.storage())
    const Values: [6] u16 = [0x0000, 0x3C00, 0x4000, 0x3800, 0xC000, 0x7BFF]
    for i in 18 do
        samples[i] = Values[i % Values.count]

    let encoded = expect source.encode("memory.exr")
    let decoded = expect Image.decode("memory.exr", nnBytes(encoded.toSlice()))
    assertImage(decoded, 3, 2, .RGBF16)
    Swag.require(Memory.compare(source.pixels.storage(), decoded.pixels.storage(), source.byteCount) == 0)
}

#test
{
    for format in [PixelFormat.GrayF16, PixelFormat.GrayAlphaF16, PixelFormat.GrayF32, PixelFormat.GrayAlphaF32]
    {
        var source = Image.create(3, 2, format)
        if format.bitDepth() == 16
        {
            let samples = cast([*] u16, source.pixels.storage())
            const Values: [6] u16 = [0x0000, 0x3400, 0x3800, 0x3C00, 0x4000, 0xC000]
            for i in source.byteCount / 2 do
                samples[i] = Values[i % Values.count]
        }
        else
        {
            let samples = cast([*] f32, source.pixels.storage())
            const Values: [6] f32 = [-2.0, -0.25, 0.0, 0.5, 1.0, 8.0]
            for i in source.byteCount / 4 do
                samples[i] = Values[i % Values.count]
        }

        let encoded = expect source.encode("gray.exr")
        let decoded = expect Image.decode("gray.exr", nnBytes(encoded.toSlice()))
        assertImage(decoded, 3, 2, format)
        Swag.require(Memory.compare(source.pixels.storage(), decoded.pixels.storage(), source.byteCount) == 0)
    }
}

#test
{
    var source  = Image.create(2, 2, .RGBAF32)
    let samples = cast([*] f32, source.pixels.storage())
    const Values: [8] f32 = [-2.0, -0.25, 0.0, 0.125, 0.5, 1.0, 4.0, 65504.0]
    for i in 16 do
        samples[i] = Values[i % Values.count]

    let encoded = expect source.encode("float.exr")
    let decoded = expect Image.decode("float.exr", nnBytes(encoded.toSlice()))
    assertImage(decoded, 2, 2, .RGBAF32)
    Swag.require(Memory.compare(source.pixels.storage(), decoded.pixels.storage(), source.byteCount) == 0)
}

#test
{
    var source = Image.create(2, 1, .RGBA8)
    let bytes  = source.pixels.storage()
    bytes[0] = 17
    bytes[1] = 34
    bytes[2] = 51
    bytes[3] = 68
    bytes[4] = 85
    bytes[5] = 102
    bytes[6] = 119
    bytes[7] = 136
    let encoded = expect source.encode("integer.exr")
    let decoded = expect Image.decode("integer.exr", nnBytes(encoded.toSlice()))
    assertImage(decoded, 2, 1, .RGBAF16)
    Swag.require(decoded.pixelColor(0, 0).argb == source.pixelColor(0, 0).argb)
    Swag.require(decoded.pixelColor(1, 0).argb == source.pixelColor(1, 0).argb)

    var options: DecodeOptions
    options.decodePixels = false
    let header = expect Image.decode("integer.exr", nnBytes(encoded.toSlice()), options)
    Swag.require(header.width == 2 and
                 header.height == 1 and
                 header.pixelFormat == .RGBAF16 and
                 not header.isValid())
}

// ZIP byte prediction and even/odd shuffling are exactly reversible before Deflate is involved.
#test
{
    var original: [257] u8
    for i in original.count do
        original[i] = cast(u8, ((i * 73 + 19) & 0xFF))
    var predicted: [257] u8
    predicted[0] = original[0]
    for i in rangeTo(1'u64, original.count - 1) do
        predicted[i] = cast(u8, ((cast(s32, original[i]) - original[i - 1] + 128) & 0xFF))
    var packed: [257] u8
    var even = 0'u64
    var odd  = (original.count + 1) / 2
    for i in original.count
    {
        if i & 1
        {
            packed[odd] = predicted[i]
            odd         += 1
        }
        else
        {
            packed[even] = predicted[i]
            even         += 1
        }
    }

    Exr.undoZipPredictor(packed)
    Swag.require(Memory.compare(original.buffer, packed.buffer, original.count) == 0)
}

#test
{
    const Invalid: [8] u8 = [0, 1, 2, 3, 4, 5, 6, 7]
    var errorOutcome: Swag.Error
    discard catch Image.decode("bad.exr", Invalid) as errorOutcome
    let error = errorOutcome.value()
    Swag.require(error != null)
}

#test
{
    let bytes = exrInvalidZipFixture()
    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try Image.decode("invalid.zip.exr", nnBytes(bytes.toSlice())) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Error: RGB and Y channels cannot be mapped to one output image without ambiguity.
#test
{
    let bytes = exrMixedRgbYFixture()
    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try Image.decode("mixed-rgb-y.exr", nnBytes(bytes.toSlice())) } as errorOutcome
    Swag.require(errorOutcome.value() is Errors.UnsupportedFormatError)
}

// EXR chunk samples may be unaligned; FLOAT reads must remain safe and little-endian.
#test
{
    let bytes   = exrUnalignedFloatFixture()
    let decoded = expect Image.decode("unaligned-float.exr", nnBytes(bytes.toSlice()))
    Swag.require(decoded.pixelFormat == .GrayF32)
    Swag.require(cast(const *f32, decoded.pixels.storage())[] == 1.0)
}
