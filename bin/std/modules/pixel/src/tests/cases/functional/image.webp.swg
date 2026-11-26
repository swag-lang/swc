#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// VP8L predictor tiles retain channel wrapping, edge handling and all predictor modes.
#test
{
    const Expected: [14] u64 = [
        0xFAE4AEBE82478458, 0x71D49ACE9BEF4DB4, 0x31594F33F04179F1, 0xF069DD1AC7A05EE4,
        0x01A164CB662FD039, 0x9795408988CC2BF4, 0xFBA9719A69AC2A4A, 0x212E3A152D9C65CC,
        0xC70E1B5E90C87493, 0xBC015A3733E8BCF3, 0x76D6355E2A138697, 0x7E360AD48D2D91F4,
        0x8594343A78099043, 0x2BD81272494568BB]
    for mode in Expected.count
    {
        var transform = Webp.LosslessTransform{oldWidth: 9, bits: 3}
        transform.pixels.resize(16)
        for tile in 4 do
            transform.pixels[tile * 4 + 1] = cast(u8, ((mode + tile) % Expected.count))

        var pixels: Array'u8
        pixels.resize(324)
        for i in pixels.count do
            pixels[i] = cast(u8, ((i * 29 + (i / 4) * 17 + i / 2) % 256))

        Webp.losslessInversePredictor(&transform, &pixels, 9)
        Swag.require(Hash.Crc64.compute(pixels.toSlice()) == Expected[mode])
    }
}

// VP8L matches can repeat an overlapping source before reaching the end of the run.
#test
{
    const Guard = 0xAF265B3D'u32
    var pixels: [80] u32
    for distance in [1'u64, 2, 3, 5, 13]
    {
        for length in [1'u64, 7, 8, 9, 11, 16, 31, 60]
        {
            for i in distance do
                pixels[i] = (cast(u32, i) + 1) * 0x01030609'u32
            pixels[distance + length] = Guard
            Webp.losslessCopyRun(&pixels[distance], distance, length)
            for i in length do
                Swag.require(pixels[distance + i] == pixels[i % distance])
            Swag.require(pixels[distance + length] == Guard)
        }
    }
}

// VP8L reads arbitrary field widths across the wide-refill boundary and the final byte.
#test
{
    const Data   = [0x6B'u8, 0x20, 0x9D, 0xF4, 0x12, 0x34, 0xC7, 0x80, 0x45, 0xBA, 0x0D, 0xE5, 0x60, 0x9F, 0xE0, 0x73]
    const Counts = [3'u32, 11, 32, 14, 32, 26, 10]
    const Fields = [3'u32, 0x40D, 0xD04BD274, 0x31C, 0x50DBA458, 0x209F60E, 0x1CF]
    let data   = cast(const [*] u8, &Data[0])
    var reader = Webp.LosslessBitReader{ptr: data, last: data + Data.count}
    for i in Counts.count
    {
        let value = expect reader.read(Counts[i])
        Swag.require(value == Fields[i])
    }

    var error: Swag.Error
    discard catch reader.read(1) as error
    Swag.require(error.value() != null)
}

// Wide refills preserve the arithmetic state and stop at every partition boundary.
#test
{
    const Data          = [0x73'u8, 0xE1, 0x0F, 0x29, 0x94, 0x55, 0x20, 0xDB, 0x42, 0x61, 0xD7, 0x13, 0x06, 0xFE, 0x67, 0xCA]
    const Probabilities = [0'u8, 255, 157, 128, 2, 46, 250, 112, 76]
    const Checkpoints   = [{bytes: 0'u32, bits: 0, code: 0'u64},
                           {bytes: 1'u32, bits: 4, code: 0x9'u64},
                           {bytes: 7'u32, bits: 94, code: 0x6E33129CDC6F551B'u64},
                           {bytes: 8'u32, bits: 111, code: 0x2539B8DEAA37B8C4'u64},
                           {bytes: 9'u32, bits: 118, code: 0x9CDC6F551BDC6236'u64},
                           {bytes: 14'u32, bits: 193, code: 0x6EF73389C6AF71BB'u64},
                           {bytes: 15'u32, bits: 213, code: 0x389C6AF71BBDCEE2'u64},
                           {bytes: 16'u32, bits: 217, code: 0x89C6AF71BBDCEE26'u64}]
    for checkpoint in Checkpoints
    {
        var partition: Webp.Vp8Partition
        partition.init(&Data[0], checkpoint.bytes)
        var bits: s32
        var code: u64
        for i in 256
        {
            let bit = partition.readBit(Probabilities[i % Probabilities.count])
            if partition.unexpectedEnd do
                break
            code = (code << 1) | cast(u64, bit)
            bits += 1
        }

        Swag.require(partition.unexpectedEnd)
        Swag.require(bits == checkpoint.bits)
        Swag.require(code == checkpoint.code)
    }
}

// Canonical byte literals must work for every bit alignment and leave the following field unread.
#test
{
    func(CHANNELS: u32) check(source: const [*] u8, shift, color: u32)
    {
        const Count = 23'u32
        const Guard = 0xE2A76D61'u32
        var actual: [Count + 2] u32
        actual[0]         = Guard
        actual[Count + 1] = Guard

        var reader    = Webp.LosslessBitReader{ptr: source, last: source + 112}
        var reference = reader
        discard expect reader.read(shift)
        discard expect reference.read(shift)
        let decoded = Webp.losslessDecodeByteLiterals'CHANNELS(&reader, &actual[1], Count, color)
        Swag.require(decoded)

        for i in Count
        {
            let code = expect reference.read(8 * CHANNELS)
            var rgba = color | (cast(u32, Webp.losslessReverseByte(cast(u8, (code & 0xFF)))) << 8)
            #static if CHANNELS >= 3
            {
                rgba |= Webp.losslessReverseByte(cast(u8, ((code >> 8) & 0xFF)))
                rgba |= cast(u32, Webp.losslessReverseByte(cast(u8, ((code >> 16) & 0xFF)))) << 16
            }

            #static if CHANNELS == 4 do
                rgba |= cast(u32, Webp.losslessReverseByte(cast(u8, (code >> 24)))) << 24
            Swag.require(actual[i + 1] == rgba)
        }

        Swag.require(actual[0] == Guard and actual[Count + 1] == Guard)
        let suffix         = expect reader.read(13)
        let expectedSuffix = expect reference.read(13)
        Swag.require(suffix == expectedSuffix)

        var short = Webp.LosslessBitReader{ptr: source, last: source + Count * CHANNELS - 1}
        discard expect short.read(shift)
        let saved  = short
        let danger = Webp.losslessDecodeByteLiterals'CHANNELS(&short, &actual[1], Count, color)
        Swag.require(not danger)
        Swag.require(short.ptr == saved.ptr and short.nBits == saved.nBits and short.bits == saved.bits)
    }

    var source: [112] u8
    for i in source.count do
        source[i] = cast(u8, ((i * 173 + 19) & 0xFF))

    for shift in 8'u32
    {
        check'1(&source[0], shift, 0xA042000F)
        check'3(&source[0], shift, 0xA0000000)
        check'4(&source[0], shift, 0)
    }
}

// The coefficient sign path matches the probability-half reader across refill and EOF boundaries.
#test
{
    const Data  = [0xE2'u8, 0x17, 0x98, 0x63, 0xCA, 0x01, 0x54, 0x7F, 0x61, 0xB3, 0x92, 0xFE, 0x88, 0x47, 0x13, 0xB2]
    const Value = 73

    for size in [1'u32, 7, 8, 9, 15, 16]
    {
        var reference, faster: Webp.Vp8Partition
        reference.init(&Data[0], size)
        faster.init(&Data[0], size)
        for index in 256
        {
            let magnitudeProbability = cast(u8, ((index * 29) & 0xFF))
            let referenceMagnitude   = reference.readBit(magnitudeProbability)
            let fasterMagnitude      = faster.readBit(magnitudeProbability)
            Swag.require(referenceMagnitude == fasterMagnitude)

            let negative    = reference.readBit(Webp.VP8_UNIFORM_PROB)
            let signedValue = faster.readCoefficientSign(Value)
            Swag.require(signedValue == (negative ? -Value : Value))
            Swag.require(reference.rangeM1 == faster.rangeM1)
            Swag.require(reference.bits == faster.bits and reference.bitCount == faster.bitCount)
            Swag.require(reference.offset == faster.offset and reference.unexpectedEnd == faster.unexpectedEnd)
            if reference.unexpectedEnd do
                break
        }

        Swag.require(reference.unexpectedEnd)
    }
}

// The DC-only inverse transform clips each block pixel without touching its neighbours.
#test
{
    var input   = [0'u8]
    var decoder = Webp.Vp8Decoder{source: &input[0]}
    for coefficient in [-32768's32, -2048, -1025, -9, -4, 0, 3, 4, 9, 1024, 2048, 32767]
    {
        decoder.coeff[0] = cast(s16, coefficient)
        let dc = (coefficient + 4) >> 3
        for x in 29's32
        {
            for row in 4's32 do
                for column in 32's32 do
                    decoder.ybr[22 + row][column] = cast(u8, ((row * 61 + column * 37 + x * 11) & 255))
            Webp.vp8InverseDct4Dc(&decoder, 22, x, 0)
            for row in 4's32
            {
                for column in 32's32
                {
                    let original = (row * 61 + column * 37 + x * 11) & 255
                    let expected = column >= x and column < x + 4 ? Math.clamp(original + dc, 0, 255) : original
                    Swag.require(decoder.ybr[22 + row][column] == expected)
                }
            }
        }
    }
}

func webpExpectedChannel(value: s32)->u8 => cast(u8, Math.clamp(value, 0, 255))

func webpMultiplyHigh(value, coefficient: s32)->s32 => (value * coefficient) >> 8

// Restore raw alpha with each predictor across short rows, vectors, and odd tails.
#test
{
    const Height = 3
    for width in [1, 15, 17, 33]
    {
        let pixels = width * Height
        var expected: [33 * Height] u8
        for i in pixels do
            expected[i] = cast #wrap(u8, (i * 57 + (i / width) * 92))
        for filter in 4
        {
            var payload: [1 + 33 * Height] u8
            payload[0] = cast(u8, filter * 4)
            for i in pixels
            {
                var prediction: s32
                if filter and i
                {
                    if i < width or (filter == 1 and i % width) do
                        prediction = expected[i - 1]
                    elif filter == 2 or i % width == 0 do
                        prediction = expected[i - width]
                    else do
                        prediction = Math.clamp(cast(s32, expected[i - 1]) + expected[i - width] - expected[i - width - 1], 0, 255)
                }

                payload[i + 1] = cast #wrap(u8, (cast(s32, expected[i]) - prediction))
            }

            let container = Webp.Container{alpha: {data: &payload[0], size: cast(u32, pixels + 1)}}
            var storage: Array'u8
            let decoded   = unwrap (expect Webp.vp8DecodeAlpha(container, width, Height, &storage))
            for i in pixels do
                Swag.require(decoded[i] == expected[i])
        }
    }
}

// The odd-sized VP8 image crosses two reconstruction window shifts and a partial final row.
#test
{
    let image = expect Image.load(getTestDataPath("vp8-row-window.webp"))
    Swag.require(image.width == 37 and image.height == 257 and image.pixelFormat == .RGBA8)
    Swag.require(Hash.Crc64.compute(image.pixels.toSlice()) == 12124014753732212138'u64)
}

// Packed conversion and its odd tail keep scalar rounding, clipping, and alpha.
#test
{
    const Width  = 33's32
    const Height = 3's32
    var input   = [0'u8]
    var decoder = Webp.Vp8Decoder{source: &input[0], header: {width: Width, height: Height}, mbWidth: 3, mbHeight: 1}
    Webp.vp8AllocatePlanes(&decoder, 1)

    var alpha: Array'u8
    alpha.resize(Width * Height)
    for row in Height
    {
        for x in Width
        {
            decoder.y[row * decoder.yStride + x] = x % 3 == 0 ? 255 : cast(u8, ((row * 23 + x * 17) % 256))
            alpha[row * Width + x] = cast(u8, ((row * 13 + x * 7) % 256))
        }

        for x in (Width + 1) / 2
        {
            decoder.cb[(row / 2) * decoder.cStride + x] = x % 3 == 0 ? 255 : cast(u8, ((x * 19) % 256))
            decoder.cr[(row / 2) * decoder.cStride + x] = cast(u8, ((x * 29) % 256))
        }
    }

    var opaque: Image
    opaque.init(Width, Height, .RGBA8)
    var rgba: Image
    rgba.init(Width, Height, .RGBA8)
    opaque.allocPixels()
    Webp.vp8WriteRgbaRow(&decoder, null, &opaque, 0, 0)
    rgba.allocPixels()
    Webp.vp8WriteRgbaRow(&decoder, alpha.buffer, &rgba, 0, 0)
    for row in Height
    {
        for x in Width
        {
            let yValue  = cast(s32, decoder.y[row * decoder.yStride + x])
            let cbValue = cast(s32, decoder.cb[(row / 2) * decoder.cStride + x / 2])
            let crValue = cast(s32, decoder.cr[(row / 2) * decoder.cStride + x / 2])
            let pixel   = rgba.pixelColor(x, row)
            let filled  = opaque.pixelColor(x, row)
            Swag.require(pixel.r == Webp.vp8YuvToR(yValue, crValue))
            Swag.require(pixel.g == Webp.vp8YuvToG(yValue, cbValue, crValue))
            Swag.require(pixel.b == Webp.vp8YuvToB(yValue, cbValue))
            Swag.require(pixel.a == alpha[row * Width + x])
            Swag.require(filled.r == pixel.r and filled.g == pixel.g and filled.b == pixel.b)
            Swag.require(filled.a == 255)
        }
    }
}

func assertWebpPixelFromTop(image: Image, x, y, r, g, b, a: u8)
{
    let color = image.pixelColor(x, y)
    Swag.require(color.r == r)
    Swag.require(color.g == g)
    Swag.require(color.b == b)
    Swag.require(color.a == a)
}

func checkWebpAgainstPng(fileName, goldenName: string, width, height: s32)
{
    let decoded = expect Image.load(getTestDataPath(fileName))
    Swag.require(decoded.isValid())
    Swag.require(decoded.width == width)
    Swag.require(decoded.height == height)
    Swag.require(decoded.pixelFormat == .RGBA8)

    let golden = expect Image.load(getTestDataPath(goldenName))
    Swag.require(golden.width == width)
    Swag.require(golden.height == height)
    for y in height do
        for x in width
        {
            let got  = decoded.pixelColor(x, y)
            let want = golden.pixelColor(x, y)
            Swag.require(got.r == want.r)
            Swag.require(got.g == want.g)
            Swag.require(got.b == want.b)
            Swag.require(got.a == want.a)
        }
}

func checkLossyWebp(fileName, goldenName: string, width, height: s32, withAlpha: bool)
{
    let decoded = expect Image.load(getTestDataPath(fileName))
    Swag.require(decoded.isValid())
    Swag.require(decoded.width == width)
    Swag.require(decoded.height == height)
    Swag.require(decoded.pixelFormat == .RGBA8)

    let golden     = expect Image.load(getTestDataPath(goldenName))
    let halfWidth  = (width + 1) / 2
    let halfHeight = (height + 1) / 2
    Swag.require(golden.width == 2 * halfWidth)
    Swag.require(golden.height == height + halfHeight + (withAlpha ? height : 0))

    for y in height
    {
        for x in width
        {
            // Both decoded images use the module's bottom-up row convention, so the reference
            // planes are read at the same internal row as the result.
            let sourceY   = y
            let luma      = cast(s32, golden.pixelColor(x, sourceY).r)
            let cb        = cast(s32, golden.pixelColor(x / 2, height + sourceY / 2).r)
            let cr        = cast(s32, golden.pixelColor(halfWidth + x / 2, height + sourceY / 2).r)
            let expectedR = webpExpectedChannel((webpMultiplyHigh(luma, 19077) + webpMultiplyHigh(cr, 26149) - 14234) >> 6)
            let expectedG = webpExpectedChannel((webpMultiplyHigh(luma, 19077) - webpMultiplyHigh(cb, 6419) - webpMultiplyHigh(cr, 13320) + 8708) >> 6)
            let expectedB = webpExpectedChannel((webpMultiplyHigh(luma, 19077) + webpMultiplyHigh(cb, 33050) - 17685) >> 6)
            let expectedA = withAlpha ? golden.pixelColor(x, height + halfHeight + sourceY).r : 0xFF
            let got       = decoded.pixelColor(x, y)
            Swag.require(got.r == expectedR)
            Swag.require(got.g == expectedG)
            Swag.require(got.b == expectedB)
            Swag.require(got.a == expectedA)
        }
    }
}

func assertEncodedWebpRoundtrip(source: Image)
{
    let buffer = expect source.encode("memory.webp")
    let bytes  = nnBytes(buffer.toSlice())
    Swag.require(bytes.count >= 21)
    Swag.require(bytes[0] == 'R' and bytes[1] == 'I' and bytes[2] == 'F' and bytes[3] == 'F')
    Swag.require(bytes[8] == 'W' and bytes[9] == 'E' and bytes[10] == 'B' and bytes[11] == 'P')
    Swag.require(bytes[12] == 'V' and bytes[13] == 'P' and bytes[14] == '8' and bytes[15] == 'L')
    let riffSize = cast(u32, bytes[4]) | (cast(u32, bytes[5]) << 8) |
                   (cast(u32, bytes[6]) << 16) | (cast(u32, bytes[7]) << 24)
    Swag.require(cast(u64, riffSize) + 8 == bytes.count)

    let decoded = expect Image.decode("encoded.webp", bytes, {})
    Swag.require(decoded.width == source.width)
    Swag.require(decoded.height == source.height)
    Swag.require(decoded.pixelFormat == .RGBA8)
    for y in source.height do
        for x in source.width
        {
            let got  = decoded.pixelColor(x, y)
            let want = source.pixelColor(x, y)
            Swag.require(got.r == want.r)
            Swag.require(got.g == want.g)
            Swag.require(got.b == want.b)
            Swag.require(got.a == want.a)
        }
}

// The decoder and encoder registries recognise WebP files.
#test
{
    Swag.require(Image.canLoad("image.webp"))
    Swag.require(not Image.canLoad("image.webm"))
    Swag.require(Image.canSave("image.webp"))
}

// Formats outside the encoder's RGB/BGR layouts are rejected explicitly.
#test
{
    var image = Image.create(1, 1, .Gray8)
    image.pixels.storage()[0] = 128'u8
    var errorOutcome: Swag.Error
    catch { discard try image.encodeToBytes("unsupported.webp") } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Lossless encoding preserves every channel and the image row orientation.
#test
{
    const pixels = [
        11'u8, 22'u8, 33'u8, 44'u8, 55'u8, 66'u8, 77'u8, 88'u8,
        91'u8, 102'u8, 113'u8, 124'u8, 135'u8, 146'u8, 157'u8, 168'u8,
        179'u8, 190'u8, 201'u8, 212'u8, 223'u8, 234'u8, 245'u8, 17'u8]
    let rgba = makeImage(3, 2, .RGBA8, pixels)
    assertEncodedWebpRoundtrip(rgba)
    assertEncodedWebpRoundtrip(rgba.convertedTo(.BGRA8))
    assertEncodedWebpRoundtrip(rgba.convertedTo(.RGB8))
    assertEncodedWebpRoundtrip(rgba.convertedTo(.BGR8))
}

// Backward-distance runs can span the VP8L maximum length and start a new run.
#test
{
    var source = Image.create(5000, 1, .RGBA8)
    source.fill(Color.fromArgb(37'u8, 19'u8, 73'u8, 211'u8))

    let buffer = expect source.encode("memory.webp")
    Swag.require(buffer.count() < 128)
    assertEncodedWebpRoundtrip(source)
}

// Empty images are rejected before a VP8L payload is created.
#test
{
    var source: Image
    var encodeErrorOutcome: Swag.Error
    discard catch source.encode("memory.webp") as encodeErrorOutcome
    let encodeError = encodeErrorOutcome.value()
    Swag.require(encodeError != null)
}

// Decode an official VP8L fixture and compare every pixel with its PNG golden image.
#test
{
    checkWebpAgainstPng("gopher-doc.lossless.webp", "gopher-doc.lossless.png", 75, 100)
    checkWebpAgainstPng("gopher-doc.with-alpha.lossless.webp", "gopher-doc.with-alpha.png", 75, 100)
}

// The VP8L color-cache hash wraps its multiplication to 32 bits.
#test
{
    let decoded = expect Image.load(getTestDataPath("color-cache.lossless.webp"))
    Swag.require(decoded.isValid())
    Swag.require(decoded.width == 32)
    Swag.require(decoded.height == 32)
    Swag.require(decoded.pixelFormat == .RGBA8)
    assertWebpPixelFromTop(decoded, 0, 0, 165, 0, 67, 255)
    assertWebpPixelFromTop(decoded, 16, 16, 173, 0, 123, 255)
}

// The VP8L predictor reconstructs each channel with modulo-256 addition.
#test
{
    let decoded = expect Image.load(getTestDataPath("transforms.lossless.webp"))
    Swag.require(decoded.isValid())
    Swag.require(decoded.width == 32)
    Swag.require(decoded.height == 32)
    Swag.require(decoded.pixelFormat == .RGBA8)
    assertWebpPixelFromTop(decoded, 31, 0, 217, 155, 147, 77)
    assertWebpPixelFromTop(decoded, 0, 31, 93, 85, 15, 201)
}

// VP8L stores signed cross-color coefficients in their raw eight-bit representation.
#test
{
    let decoded = expect Image.load(getTestDataPath("cross-color.lossless.webp"))
    Swag.require(decoded.isValid())
    Swag.require(decoded.width == 32)
    Swag.require(decoded.height == 32)
    Swag.require(decoded.pixelFormat == .RGBA8)
    assertWebpPixelFromTop(decoded, 0, 0, 255, 0, 255, 255)
    assertWebpPixelFromTop(decoded, 16, 16, 31, 224, 79, 255)
}

// Metadata-only decoding reads dimensions without allocating the pixel buffer.
#test
{
    let bytes = expect File.readAllBytes(getTestDataPath("gopher-doc.lossless.webp"))
    var options: DecodeOptions
    options.decodePixels = false
    let decoded = expect Image.decode("metadata.webp", bytes.toSlice(), options)
    Swag.require(decoded.width == 75)
    Swag.require(decoded.height == 100)
    Swag.require(decoded.pixelFormat == .RGBA8)
    Swag.require(not decoded.isValid())
}

// Invalid and truncated RIFF data fails before allocating an image.
#test
{
    let bad: [12] u8 = [
        'R', 'I', 'F', 'F', 4, 0, 0, 0, 'N', 'O', 'P', 'E']
    var decoded:     Image
    var err5Outcome: Swag.Error
    catch { decoded = try Image.decode("bad.webp", Swag.makeSlice(&bad[0], bad.count), {}) } as err5Outcome
    let err5 = err5Outcome.value()
    Swag.require(err5 != null)

    let bytes = expect File.readAllBytes(getTestDataPath("gopher-doc.lossless.webp"))
    var err7Outcome: Swag.Error
    catch { decoded = try Image.decode("truncated.webp", Swag.makeSlice(bytes.buffer, 32), {}) } as err7Outcome
    let err7 = err7Outcome.value()
    Swag.require(err7 != null)
}

#test
{
    var bytes = expect File.readAllBytes(getTestDataPath("blue-purple-pink.lossy.webp"))
    var cursor:      u64 = 12
    var frameOffset: u64
    while cursor + 8 <= bytes.count
    {
        if bytes[cursor + 0] == 'V' and
           bytes[cursor + 1] == 'P' and
           bytes[cursor + 2] == '8' and
           bytes[cursor + 3] == ' '
        {
            frameOffset = cursor + 8
            break
        }

        let size = cast(u64, bytes[cursor + 4]) |
                   (cast(u64, bytes[cursor + 5]) << 8) |
                   (cast(u64, bytes[cursor + 6]) << 16) |
                   (cast(u64, bytes[cursor + 7]) << 24)
        cursor += 8 + size + (size & 1)
    }

    Swag.require(frameOffset > 0)
    let frameTag = bytes[frameOffset]
    bytes[frameOffset] = (frameTag & 0xF1) | 0x08

    var image: Image
    var versionErrorOutcome: Swag.Error
    catch { image = try Image.decode("reserved-version.webp", bytes.toSlice()) } as versionErrorOutcome
    Swag.require(versionErrorOutcome.value() != null)

    bytes[frameOffset] = frameTag & 0xEF
    var showFrameErrorOutcome: Swag.Error
    catch { image = try Image.decode("hidden-frame.webp", bytes.toSlice()) } as showFrameErrorOutcome
    Swag.require(showFrameErrorOutcome.value() != null)
}

// Error: ANMF flags may only set disposal and blend bits.
#test
{
    var bytes = expect File.readAllBytes(getTestDataPath("imageset-animation.webp"))
    bytes[67] |= 4     // First ANMF frame flags: only bits 0 and 1 are defined.
    var reader:       ImageReader
    var errorOutcome: Swag.Error
    catch { reader = try ImageReader.decode("reserved-frame-flags.webp", bytes.toSlice()) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Decode a VP8 fixture and compare it with the official split-plane YCbCr golden image.
#test
{
    checkLossyWebp("blue-purple-pink.lossy.webp", "blue-purple-pink.lossy.webp.ycbcr.png", 150, 100, false)

    let decoded = expect Image.load(getTestDataPath("blue-purple-pink.lossy.webp"))

    // Reference samples produced by libwebp 1.6.0 dwebp with -nofancy.
    assertWebpPixelFromTop(decoded, 0, 0, 16, 19, 15, 255)
    assertWebpPixelFromTop(decoded, 112, 58, 232, 107, 160, 255)
    assertWebpPixelFromTop(decoded, 32, 41, 38, 70, 151, 255)
    assertWebpPixelFromTop(decoded, 79, 36, 255, 219, 255, 255)
}

// Decode VP8 with a compressed ALPH chunk and verify color and alpha planes.
#test
{
    checkLossyWebp("yellow_rose.lossy-with-alpha.webp", "yellow_rose.lossy-with-alpha.webp.nycbcra.png", 400, 301, true)

    let decoded = expect Image.load(getTestDataPath("yellow_rose.lossy-with-alpha.webp"))

    // Reference samples produced by libwebp 1.6.0 dwebp with -nofancy.
    assertWebpPixelFromTop(decoded, 106, 81, 241, 146, 3, 255)
    assertWebpPixelFromTop(decoded, 128, 47, 255, 90, 151, 255)
    assertWebpPixelFromTop(decoded, 160, 40, 255, 212, 232, 255)
    assertWebpPixelFromTop(decoded, 78, 0, 255, 221, 165, 0)
}

// Exercise no, simple and normal VP8 loop filters against official golden planes.
#test
{
    checkLossyWebp("blue-purple-pink-large.no-filter.lossy.webp",
                   "blue-purple-pink-large.no-filter.lossy.webp.ycbcr.png",
                   600,
                   400,
                   false)
    checkLossyWebp("blue-purple-pink-large.simple-filter.lossy.webp",
                   "blue-purple-pink-large.simple-filter.lossy.webp.ycbcr.png",
                   600,
                   400,
                   false)
    checkLossyWebp("blue-purple-pink-large.normal-filter.lossy.webp",
                   "blue-purple-pink-large.normal-filter.lossy.webp.ycbcr.png",
                   600,
                   400,
                   false)
}

// Multiple VP8 coefficient partitions decode independently.
#test
{
    checkLossyWebp("video-001.lossy.webp", "video-001.lossy.webp.ycbcr.png", 150, 103, false)
}

// VP8 metadata-only decoding reads the frame header without allocating pixels.
#test
{
    let bytes = expect File.readAllBytes(getTestDataPath("blue-purple-pink.lossy.webp"))
    var options: DecodeOptions
    options.decodePixels = false
    let decoded = expect Image.decode("metadata.webp", bytes.toSlice(), options)
    Swag.require(decoded.width == 150)
    Swag.require(decoded.height == 100)
    Swag.require(decoded.pixelFormat == .RGBA8)
    Swag.require(not decoded.isValid())
}

// Animated WebP is rejected because Image represents one static image.
#test
{
    let animated: [30] u8 = [
        'R', 'I', 'F', 'F', 22, 0, 0, 0, 'W', 'E', 'B', 'P',
        'V', 'P', '8', 'X', 10, 0, 0, 0,
        2, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    var decoded: Image
    var decodeErrorOutcome: Swag.Error
    catch { decoded = try Image.decode("animated.webp", Swag.makeSlice(&animated[0], animated.count), {}) } as decodeErrorOutcome
    let decodeError = decodeErrorOutcome.value()
    Swag.require(decodeError != null)
}
