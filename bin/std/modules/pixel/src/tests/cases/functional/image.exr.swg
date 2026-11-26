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

func exrZipFixture(width: u32, packed: const [..] u8)->ConcatBuffer
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
    exrAddU32(&dataWindow, width - 1)
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
    exrAddU32(&result, cast(u32, packed.count))
    result.addBytes(packed)
    return result
}

func exrMixedRgbYFixture()->ConcatBuffer
{
    var channels: ConcatBuffer
    for name in ["B", "G", "R", "Y"]
    {
        exrAddText(&channels, name)
        exrAddU32(&channels, 1)     // HALF channel.
        exrAddU32(&channels, 0)
        exrAddU32(&channels, 1)
        exrAddU32(&channels, 1)
    }

    channels.addNative(0'u8)

    var compression: [1] u8 = [0]     // No compression.
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

func exrUnalignedFloatFixture(names: const [..] string, width = 1'u32)->ConcatBuffer
{
    var channels: ConcatBuffer
    var samples:  ConcatBuffer
    for name in names
    {
        exrAddText(&channels, name)
        exrAddU32(&channels, name == "A" or name == "B" ? 1 : 2)
        exrAddU32(&channels, 0)
        exrAddU32(&channels, 1)
        exrAddU32(&channels, 1)

        for width
        {
            switch name
            {
            case "A":
                samples.addNative(0x3800'u16)     // Half 0.5.

            case "B":
                samples.addNative(0x0001'u16)     // Smallest half subnormal.

            case "G":
                exrAddU32(&samples, 0x80000000)     // Float -0.0.

            case "R", "Y":
                exrAddU32(&samples, 0x3F800000)     // Float 1.0.
            }
        }
    }

    channels.addNative(0'u8)

    var compression: [1] u8 = [0]     // No compression.
    var dataWindow:  ConcatBuffer
    exrAddU32(&dataWindow, 0)
    exrAddU32(&dataWindow, 0)
    exrAddU32(&dataWindow, width - 1)
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
    let tableEnd    = result.count() + 8
    let chunkOffset = tableEnd + (tableEnd & 1 ? 0 : 1)
    exrAddU64(&result, chunkOffset)
    while result.count() < chunkOffset do
        result.addNative(0'u8)
    exrAddU32(&result, 0)     // First scanline.
    exrAddU32(&result, cast(u32, samples.count()))
    result.addBytes(unwrap samples.toSlice())
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
    const Values:   [10] u16 = [0x0001, 0x3C00, 0x4000, 0x8000, 0xC000, 0x7BFF, 0x7C00, 0x7CF1, 0xFE03, 0xFC00]
    const Expected: [10] u16 = [0x0001, 0x3C00, 0x4000, 0x8000, 0xC000, 0x7BFF, 0x7C00, 0x7E00, 0xFE00, 0xFC00]

    // Exercise complete vectors, scalar tails, and rows that start at unaligned addresses.
    for format in [PixelFormat.RGBF16, PixelFormat.RGBAF16]
    {
        for width in [1, 7, 8, 9, 15, 16, 17]
        {
            var source  = Image.create(width, 2, format)
            let samples = cast([*] u16, source.pixels.storage())
            for i in source.byteCount / 2 do
                samples[i] = Values[i % Values.count]

            let encoded = expect source.encode("memory.exr")
            let decoded = expect Image.decode("memory.exr", nnBytes(encoded.toSlice()))
            assertImage(decoded, width, 2, format)

            // Preserve finite samples, signed zero, infinity, and each NaN's sign.
            let decodedSamples = cast(const [*] u16, decoded.pixels.storage())
            for i in source.byteCount / 2 do
                Swag.require(decodedSamples[i] == Expected[i % Expected.count])
        }
    }
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
    const Values: [10] u32 = [0x0000_0001, 0x3F00_0000, 0x8000_0000, 0x4000_0000, 0xC000_0000,
                              0x7F7F_FFFF, 0x7F80_0000, 0x7FA0_0130, 0xFFC0_2203, 0xFF80_0000]
    for format in [PixelFormat.RGBF32, PixelFormat.RGBAF32]
    {
        for width in [3, 4, 5, 9]
        {
            var source  = Image.create(width, 2, format)
            let samples = cast([*] u32, source.pixels.storage())
            for i in source.byteCount / 4 do
                samples[i] = Values[i % Values.count]

            let encoded = expect source.encode("float.exr")
            let decoded = expect Image.decode("float.exr", nnBytes(encoded.toSlice()))
            assertImage(decoded, width, 2, format)
            Swag.require(Memory.compare(source.pixels.storage(), decoded.pixels.storage(), source.byteCount) == 0)
        }
    }
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
    var packed: [257] u8
    var even = 0'u64
    var odd  = (original.count + 1) / 2
    for i in original.count
    {
        if i & 1
        {
            packed[odd] = original[i]
            odd         += 1
        }
        else
        {
            packed[even] = original[i]
            even         += 1
        }
    }

    var previous = packed[0]
    for i in rangeTo(1'u64, packed.count - 1)
    {
        let current = packed[i]
        packed[i] = cast(u8, ((cast(s32, current) - previous + 128) & 0xFF))
        previous  = current
    }

    var restored: Array'u8
    Exr.undoZipPredictor(packed, &restored)
    Swag.require(restored.count == original.count)
    Swag.require(Memory.compare(original.buffer, restored.storage(), original.count) == 0)
}

// OpenEXR 3.1 produced two compressed ZIP chunks (16 and 3 rows) and three raw ZIPS rows.
#test
{
    let fixtures = [{name: "exr-zip-scanlines.exr", width: 17, height: 19},
                    {name: "exr-zips-stored.exr", width: 1, height: 3}]
    const Red: [3] u16 = [0x0000, 0x3400, 0x3C00]
    for fixture in fixtures
    {
        let decoded = expect Image.load(getTestDataPath(fixture.name))
        assertImage(decoded, fixture.width, fixture.height, .RGBAF16)
        let samples = cast(const [*] u16, decoded.pixels.storage())
        for y in decoded.height
        {
            for x in decoded.width
            {
                let index = ((decoded.height - y - 1) * decoded.width + x) * 4
                Swag.require(samples[index] == Red[x % Red.count])
                Swag.require(samples[index + 1] == (y & 1 ? 0xC000 : 0x4000))
                Swag.require(samples[index + 2] == (x & 1 ? 0x3800 : 0x3E00))
                Swag.require(samples[index + 3] == 0x3C00)
            }
        }
    }
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
    const InvalidZlib: [7] u8 = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
    let bytes = exrZipFixture(4, InvalidZlib)
    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try Image.decode("invalid.zip.exr", nnBytes(bytes.toSlice())) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// ZIP inflation stops at the scanline size declared by the data window.
#test
{
    var oversized: [64] u8
    var zlib:      Compress.ZLib
    let packed = expect zlib.compress(oversized)
    Swag.require(packed.count < 32)
    let bytes = exrZipFixture(16, packed.toSlice())
    var errorOutcome: Swag.Error
    discard catch Image.decode("oversized-zips.exr", nnBytes(bytes.toSlice())) as errorOutcome
    Swag.require(errorOutcome.value() is Errors.UnsupportedFormatError)
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
    let bytes   = exrUnalignedFloatFixture(["Y"])
    let decoded = expect Image.decode("unaligned-float.exr", nnBytes(bytes.toSlice()))
    Swag.require(decoded.pixelFormat == .GrayF32)
    Swag.require(cast(const *f32, decoded.pixels.storage())[] == 1.0)
}

#test
{
    for width in [1'u32, 4, 5, 9]
    {
        let bytes   = exrUnalignedFloatFixture(["A", "B", "G", "R"], width)
        let decoded = expect Image.decode("unaligned-mixed.exr", nnBytes(bytes.toSlice()))
        assertImage(decoded, cast(s32, width), 1, .RGBAF32)
        let samples = cast(const [*] u32, decoded.pixels.storage())
        for pixel in width
        {
            Swag.require(samples[pixel * 4] == 0x3F800000)
            Swag.require(samples[pixel * 4 + 1] == 0x80000000)
            Swag.require(samples[pixel * 4 + 2] == 0x33800000)
            Swag.require(samples[pixel * 4 + 3] == 0x3F000000)
        }
    }
}

#test
{
    var source: [4] u16
    for block in 16384'u64
    {
        for lane in 4'u64 do
            source[lane] = cast(u16, block * 4 + lane)
        let wide = cast #bit(Math.Simd.U32x4, Exr.widenHalfSamples(cast(const [*] u8, source.buffer)))
        for lane in 4'u64 do
            Swag.require(wide[lane] == cast #bit(u32, halfToFloat(source[lane])))
    }
}
