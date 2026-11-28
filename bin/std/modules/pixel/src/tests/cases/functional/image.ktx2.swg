#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func ktx2Roundtrip(source: Image)->Image
{
    let encoded = expect source.encode("memory.ktx2")
    return expect Image.decode("roundtrip.ktx2", nnBytes(encoded.toSlice()))
}

#test
{
    const Formats: [18] PixelFormat = [.Gray8, .GrayAlpha8, .Gray16, .GrayAlpha16, .GrayF16, .GrayAlphaF16,
                                       .GrayF32, .GrayAlphaF32, .BGR8, .BGRA8, .RGB8, .RGBA8,
                                       .RGB16, .RGBA16, .RGBF16, .RGBAF16, .RGBF32, .RGBAF32]
    for format in Formats
    {
        var source = Image.create(5, 3, format)
        for i in source.byteCount
        {
            source.pixels.storage()[i] = cast(u8, ((i * 37 + 11) & 0xFF))
        }

        let decoded = ktx2Roundtrip(source)
        assertImage(decoded, source.width, source.height, format)
        Swag.require(Memory.compare(source.pixels.storage(), decoded.pixels.storage(), source.byteCount) == 0)
    }
}

// KTX2 decompresses a level under its validated decoded byte count before copying pixels.
#test
{
    var source = Image.create(32, 32, .RGBA8)
    source.fill(Color.fromArgb(123, 17, 34, 51))
    var encoded = expect source.encode("plain.ktx2")
    encoded.makeLinear()
    var plain      = unwrap encoded.toSlice()
    let dataOffset = cast(const *u64, (plain.buffer + 80))[]
    let rawLength  = cast(const *u64, (plain.buffer + 96))[]
    let level      = plain[dataOffset until dataOffset + rawLength]
    var oversized: Array!{u8}
    oversized.add(level)
    oversized.add(0)

    for scheme in [2_u8, 3]
    {
        var zlib: Compress.ZLib
        for invalid in [false, true]
        {
            let input      = invalid ? oversized.toSlice() : level
            let compressed = scheme == 2 ? Compress.Zstd.compress(input) : expect zlib.compress(input)

            plain[44] = scheme
            cast(*u64, (plain.buffer + 88))[] = compressed.count
            var rebuilt: ConcatBuffer
            rebuilt.addBytes(plain[until dataOffset])
            rebuilt.addBytes(compressed.toSlice())

            if invalid
            {
                var failure: Swag.Error
                discard catch Image.decode("compressed.ktx2", nnBytes(rebuilt.toSlice())) as failure
                Swag.require(failure.value() != null)
            }
            else
            {
                let decoded = expect Image.decode("compressed.ktx2", nnBytes(rebuilt.toSlice()))
                assertImage(decoded, 32, 32, .RGBA8)
                Swag.require(Memory.compare(source.pixels.storage(), decoded.pixels.storage(), source.byteCount) == 0)
            }
        }
    }
}

#test
{
    var source = Image.create(3, 2, .RGB16)
    source.clear()
    var encoded = expect source.encode("probe.ktx2")
    var options: DecodeOptions
    options.decodePixels = false
    let header = expect Image.decode("probe.ktx2", nnBytes(encoded.toSlice()), options)
    Swag.require(header.width == 3 and
                 header.height == 2 and
                 header.pixelFormat == .RGB16 and
                 not header.isValid())

    encoded.makeLinear()
    var bytes = unwrap encoded.toSlice()
    cast(*u32, bytes.buffer + 20)[] = 400_000_000

    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try Image.decode("oversized.ktx2", bytes) } as errorOutcome
    Swag.require(errorOutcome.value() != null)

    options.maxPixels       = 0
    options.maxDecodedBytes = 0
    errorOutcome            = {}
    catch { image = try Image.decode("oversized.ktx2", bytes, options) } as errorOutcome
    Swag.require(errorOutcome.value() != null)

    const Invalid: [12] u8 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
    errorOutcome = {}
    discard catch Image.decode("bad.ktx2", Invalid) as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Error: KTXorientation needs one direction for each texture dimension.
#test
{
    var source  = Image.create(1, 1, .RGBA8)
    var encoded = expect source.encode("short-orientation.ktx2")
    encoded.makeLinear()
    var bytes     = unwrap encoded.toSlice()
    let kvdOffset = cast(u32, bytes.count)
    cast(*u32, bytes.buffer + 56)[] = kvdOffset
    cast(*u32, bytes.buffer + 60)[] = 20

    var fixture: ConcatBuffer
    fixture.addBytes(bytes)
    fixture.addNative(16_u32)     // key plus NUL and one value byte
    fixture.addBytes("KTXorientation")
    fixture.addNative(0_u8)
    fixture.addNative('r')

    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try Image.decode("short-orientation.ktx2", nnBytes(fixture.toSlice())) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Decode Khronos RGBA8 packed textures with both vertical orientations.
#test
{
    const Names: [2] string = ["ktx2-rgba-packed-unorm.ktx2", "ktx2-rgba-packed-srgb.ktx2"]
    const Crcs:  [2] u64    = [11740699541499367249_u64, 6821568150130671602_u64]
    for name, index in Names
    {
        let path  = getTestDataPath(name)
        let image = expect Image.load(path)
        assertImage(image, 3, 5, .RGBA8)
        Swag.require(Hash.Crc64.compute(image.pixels.toSlice()) == Crcs[index])

        var reader = expect ImageReader.load(path)
        let frame  = expect reader.read(0)
        Swag.require(Slice.equals(image.pixels.toSlice(), frame.pixels.toSlice()))
    }
}

// Accept older orientation strings without a NUL, and reject a non-NUL suffix.
#test
{
    const Name = "ktx2-rgba-packed-srgb.ktx2"
    var fixture  = expect File.readAllBytes(getTestDataPath(Name))
    let metadata = cast(const *u32, fixture.storage() + 56)[]
    let entry    = cast(*u32, fixture.storage() + metadata)
    let suffix   = metadata + 4 + entry[] - 1
    fixture[suffix] = 'x'
    var failure: Swag.Error
    discard catch Image.decode(Name, fixture.toSlice()) as failure
    Swag.require(failure.value() != null)

    // The original padding still keeps the next metadata entry aligned.
    entry[] -= 1
    let image = expect Image.decode(Name, fixture.toSlice())
    Swag.require(Hash.Crc64.compute(image.pixels.toSlice()) == 6821568150130671602_u64)
}

// BC7 sRGB retains its stored values and clips both edges of its last block row.
#test
{
    let path   = getTestDataPath("bc7-srgb-clipped.ktx2")
    let result = expect Image.load(path)
    assertImage(result, 13, 7, .RGBA8)
    Swag.require(Hash.Crc64.compute(result.pixels.toSlice()) == 1839993950864328395_u64)

    var reader = expect ImageReader.load(path)
    let frame  = expect reader.read(0)
    Swag.require(Slice.equals(result.pixels.toSlice(), frame.pixels.toSlice()))
}

// Four-byte rows reverse in complete vectors with a separate odd-height tail.
#test
{
    for format in [PixelFormat.RGBA8, PixelFormat.GrayAlpha16]
    {
        var source = Image.create(1, 259, format)
        for index in source.pixels.count
        {
            source.pixels[index] = cast #wrap(u8, index * 37 + index / 11)
        }

        let decoded = ktx2Roundtrip(source)
        assertImage(decoded, source.width, source.height, format)
        Swag.require(Slice.equals(source.pixels.toSlice(), decoded.pixels.toSlice()))
    }
}
