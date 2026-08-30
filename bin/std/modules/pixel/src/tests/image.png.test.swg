#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// The high-level memory encoder mirrors `Image.decode` without touching the file system.
#test
{
    var source = Image.create(2, 1, .RGBA8)
    source.fill(Color.fromArgb(200'u8, 10'u8, 20'u8, 30'u8))

    var encoded = expect source.encode("memory.png")
    encoded.makeLinear()
    let bytes = nnBytes(encoded.toSlice())
    Swag.assert(bytes.count > 8)

    let decoded = expect Image.decode("memory.png", bytes)
    assertImage(decoded, 2, 1, .RGBA8)
    Swag.assert(Memory.compare(source.pixels.buffer, decoded.pixels.buffer, source.byteCount) == 0)
}

func assertPngPixelAt(img: Image, x, yFromBottom: s32, r, g, b, a: u8)
{
    let color = img.pixelColor(x, img.height - yFromBottom - 1)
    Swag.assert(color.r == r)
    Swag.assert(color.g == g)
    Swag.assert(color.b == b)
    Swag.assert(color.a == a)
}

func assertLoadedPng(fileName: string, width, height: s32, pf: PixelFormat, r, g, b, a: u8)
{
    let img = expect Image.load(getTestDataPath(fileName))
    Swag.assert(img.isValid())
    Swag.assert(img.width == width)
    Swag.assert(img.height == height)
    Swag.assert(img.pixelFormat == pf)
    Swag.assert(img.bitsPerPixel == pf.bitsPerPixel())
    Swag.assert(img.bytesPerPixel == pf.channels())
    Swag.assert(img.pixels.count == cast(u64) width * height * img.bytesPerPixel)
    assertPngPixelAt(img, 0, 0, r, g, b, a)
}

func assertPngHasChunk(bytes: const [..] u8, c0, c1, c2, c3: u8)
{
    var i = 8'u64
    while i + 12 <= bytes.count
    {
        if bytes[i + 4] == c0 and bytes[i + 5] == c1 and bytes[i + 6] == c2 and bytes[i + 7] == c3 do
            return

        let length = (cast(u64) bytes[i] << 24) | (cast(u64) bytes[i + 1] << 16) | (cast(u64) bytes[i + 2] << 8) | cast(u64) bytes[i + 3]
        i += length + 12
    }

    Swag.assert(false)
}

func assertEncodedPngRoundtrip(src: Image, expectedPf: PixelFormat, options: #null any = null)
{
    let cb    = expect src.encode("memory.png", options)
    let bytes = nnBytes(cb.toSlice())
    Swag.assert(bytes.count > 33)
    Swag.assert(bytes[0] == 137'u8 and bytes[1] == 80'u8 and bytes[2] == 78'u8 and bytes[3] == 71'u8)
    assertPngHasChunk(bytes, 73'u8, 72'u8, 68'u8, 82'u8)
    assertPngHasChunk(bytes, 73'u8, 68'u8, 65'u8, 84'u8)
    assertPngHasChunk(bytes, 73'u8, 69'u8, 78'u8, 68'u8)

    let img = expect Image.decode("encoded.png", bytes, {})
    Swag.assert(img.width == src.width)
    Swag.assert(img.height == src.height)
    Swag.assert(img.pixelFormat == expectedPf)
    Swag.assert(img.pixels.count == src.pixels.count)
    Swag.assert(Memory.compare(src.pixels.buffer, img.pixels.buffer, src.pixels.count) == 0)
}

func fillSolidPngImage(img: *Image, r, g, b, a: u8)
{
    var pix = img.pixels.buffer!
    for img.width * img.height
    {
        switch img.pixelFormat
        {
        case .BGR8:
            pix[0] = b
            pix[1] = g
            pix[2] = r

        case .RGB8:
            pix[0] = r
            pix[1] = g
            pix[2] = b

        case .BGRA8:
            pix[0] = b
            pix[1] = g
            pix[2] = r
            pix[3] = a

        case .RGBA8:
            pix[0] = r
            pix[1] = g
            pix[2] = b
            pix[3] = a
        }

        pix += img.bytesPerPixel
    }
}

#test
{
    // SIMD strides and scalar fallbacks agree for every vector/tail boundary,
    // unaligned pointer, carry between blocks, modulo wrap, and sentinel.
    const Capacity = 192
    var source:   [Capacity] u8
    var actual:   [Capacity] u8
    var expected: [Capacity] u8
    for bytesPerPixelIndex in 8
    {
        let bytesPerPixel = bytesPerPixelIndex + 1
        for count in 162
        {
            for i in Capacity
            {
                source[i]   = cast(u8) ((cast(u32) i * 37 + cast(u32) count * 11 + cast(u32) bytesPerPixel * 17) & 0xFF)
                actual[i]   = 0xA5
                expected[i] = 0xA5
            }

            source[1] = 255
            for i in count
            {
                let left  = i >= bytesPerPixel ? expected[3 + i - bytesPerPixel] : 0'u8
                let value = cast(u16) source[1 + i] + left
                expected[3 + i] = cast(u8) (value & 0xFF)
            }

            Png.defilterSubRow(&source[1], &actual[3], count, bytesPerPixel)
            for i in Capacity do
                Swag.assert(actual[i] == expected[i])
        }
    }
}

#test
{
    // The packed reconstruction carries the left pixel in a register and writes eight bytes a
    // step, so this covers every pixel stride, both sides of that eight-byte window, the bytes
    // a step writes past its own pixel, unaligned pointers, and the sentinel around the row.
    const Capacity = 192
    var source:   [Capacity] u8
    var previous: [Capacity] u8
    var actual:   [Capacity] u8
    var expected: [Capacity] u8
    for bytesPerPixelIndex in 8
    {
        let bytesPerPixel = bytesPerPixelIndex + 1
        for count in 162
        {
            for i in Capacity
            {
                source[i]   = cast(u8) ((cast(u32) i * 37 + cast(u32) count * 11 + cast(u32) bytesPerPixel * 17) & 0xFF)
                previous[i] = cast(u8) ((cast(u32) i * 53 + cast(u32) count * 7) & 0xFF)
                actual[i]   = 0xA5
                expected[i] = 0xA5
            }

            source[1]   = 255
            previous[2] = 255

            for i in count
            {
                let left    = i >= bytesPerPixel ? expected[3 + i - bytesPerPixel] : 0'u8
                let average = cast(u8) ((cast(u16) previous[2 + i] + left) >> 1)
                expected[3 + i] = cast(u8) ((cast(u16) source[1 + i] + average) & 0xFF)
            }

            Png.defilterAverageRow(&source[1], &previous[2], &actual[3], count, bytesPerPixel)
            for i in Capacity do
                Swag.assert(actual[i] == expected[i])
        }
    }
}

#test
{
    // Same coverage as the Average reconstruction, plus the Paeth ties: the extremes planted in
    // the first two pixels make the three distances collide, which is where a packed predictor
    // and the ordered scalar comparisons part company if the preference order is wrong.
    const Capacity = 192
    var source:   [Capacity] u8
    var previous: [Capacity] u8
    var actual:   [Capacity] u8
    var expected: [Capacity] u8
    for bytesPerPixelIndex in 8
    {
        let bytesPerPixel = bytesPerPixelIndex + 1
        for count in 162
        {
            for i in Capacity
            {
                source[i]   = cast(u8) ((cast(u32) i * 37 + cast(u32) count * 11 + cast(u32) bytesPerPixel * 17) & 0xFF)
                previous[i] = cast(u8) ((cast(u32) i * 53 + cast(u32) count * 7) & 0xFF)
                actual[i]   = 0xA5
                expected[i] = 0xA5
            }

            source[1]                   = 0
            source[1 + bytesPerPixel]   = 255
            previous[2]                 = 255
            previous[2 + bytesPerPixel] = 0

            for i in count
            {
                let left      = i >= bytesPerPixel ? expected[3 + i - bytesPerPixel] : 0'u8
                let upLeft    = i >= bytesPerPixel ? previous[2 + i - bytesPerPixel] : 0'u8
                let predictor = Png.filterPaeth(left, previous[2 + i], upLeft)
                expected[3 + i] = cast(u8) ((cast(u16) source[1 + i] + predictor) & 0xFF)
            }

            Png.defilterPaethRow(&source[1], &previous[2], &actual[3], count, bytesPerPixel)
            for i in Capacity do
                Swag.assert(actual[i] == expected[i])
        }
    }
}

#test
{
    // Every pixel stride, vector/tail boundary, unaligned pointer, Paeth tie,
    // extreme predictor, wrapping subtraction, and sentinel matches scalar.
    //
    // A score reads the residual as the byte PNG stores, so it is never negative:
    // scoring the signed difference lets a noisy row cancel itself out.
    const Capacity = 192
    var source:   [Capacity] u8
    var previous: [Capacity] u8
    var actual:   [Capacity] u8
    var expected: [Capacity] u8
    for bytesPerPixelIndex in 8
    {
        let bytesPerPixel = bytesPerPixelIndex + 1
        for count in 162
        {
            for i in Capacity
            {
                source[i]   = cast(u8) ((cast(u32) i * 37 + cast(u32) count * 11 + cast(u32) bytesPerPixel * 17) & 0xFF)
                previous[i] = cast(u8) ((cast(u32) i * 53 + cast(u32) count * 7) & 0xFF)
                actual[i]   = 0xA5
                expected[i] = 0xA5
            }

            source[1]                   = 0
            source[1 + bytesPerPixel]   = 255
            previous[2]                 = 255
            previous[2 + bytesPerPixel] = 0
            var expectedScore = 0's32
            for i in count
            {
                let left      = i >= bytesPerPixel ? source[1 + i - bytesPerPixel] : 0'u8
                let upLeft    = i >= bytesPerPixel ? previous[2 + i - bytesPerPixel] : 0'u8
                let predictor = Png.paethScalar(left, previous[2 + i], upLeft)
                let value     = cast #bit(u8) (cast(s32) source[1 + i] - predictor)
                expected[3 + i] = value
                expectedScore   += 128 - Math.abs(cast(s32) value - 128)
            }

            Png.filterPaethRow(&source[1], &previous[2], &actual[3], count, bytesPerPixel)
            for i in Capacity do
                Swag.assert(actual[i] == expected[i])
            Swag.assert(Png.filterSumPaeth(&source[1], &previous[2], count, bytesPerPixel) == expectedScore)
        }
    }
}

#test
{
    // Every pixel stride, vector/tail boundary, unaligned pointer, odd average,
    // wrapping subtraction, and untouched sentinel matches the scalar form.
    const Capacity = 192
    var source:   [Capacity] u8
    var previous: [Capacity] u8
    var actual:   [Capacity] u8
    var expected: [Capacity] u8
    for bytesPerPixelIndex in 8
    {
        let bytesPerPixel = bytesPerPixelIndex + 1
        for count in 162
        {
            for i in Capacity
            {
                source[i]   = cast(u8) ((cast(u32) i * 37 + cast(u32) count * 11 + cast(u32) bytesPerPixel * 17) & 0xFF)
                previous[i] = cast(u8) ((cast(u32) i * 53 + cast(u32) count * 7 + 1) & 0xFF)
                actual[i]   = 0xA5
                expected[i] = 0xA5
            }

            var expectedScore = 0's32
            for i in count
            {
                let left    = i >= bytesPerPixel ? source[1 + i - bytesPerPixel] : 0'u8
                let average = (cast(s32) left + previous[2 + i]) / 2
                let value   = cast #bit(u8) (cast(s32) source[1 + i] - average)
                expected[3 + i] = value
                expectedScore   += 128 - Math.abs(cast(s32) value - 128)
            }

            Png.filterAverageRow(&source[1], &previous[2], &actual[3], count, bytesPerPixel)
            for i in Capacity do
                Swag.assert(actual[i] == expected[i])
            Swag.assert(Png.filterSumAverage(&source[1], &previous[2], count, bytesPerPixel) == expectedScore)
        }
    }
}

#test
{
    // Every pixel stride, vector/tail boundary, unaligned pointer, wrapping
    // subtraction, and untouched destination sentinel matches the scalar form.
    const Capacity = 192
    var source:   [Capacity] u8
    var actual:   [Capacity] u8
    var expected: [Capacity] u8
    for bytesPerPixelIndex in 8
    {
        let bytesPerPixel = bytesPerPixelIndex + 1
        for count in 162
        {
            for i in Capacity
            {
                source[i]   = cast(u8) ((cast(u32) i * 37 + cast(u32) count * 11 + cast(u32) bytesPerPixel * 17) & 0xFF)
                actual[i]   = 0xA5
                expected[i] = 0xA5
            }

            source[1]                 = 0
            source[1 + bytesPerPixel] = 255
            var expectedScore = 0's32
            for i in count
            {
                let left  = i >= bytesPerPixel ? source[1 + i - bytesPerPixel] : 0'u8
                let value = cast #bit(u8) (cast(s32) source[1 + i] - left)
                expected[3 + i] = value
                expectedScore   += 128 - Math.abs(cast(s32) value - 128)
            }

            Png.filterSubRow(&source[1], &actual[3], count, bytesPerPixel)
            for i in Capacity do
                Swag.assert(actual[i] == expected[i])
            Swag.assert(Png.filterSumSub(&source[1], count, bytesPerPixel) == expectedScore)
        }
    }
}

#test
{
    // SIMD and scalar definitions agree at every vector/tail boundary, with
    // unaligned pointers and the full positive/negative byte-difference range.
    const Capacity = 192
    var source:   [Capacity] u8
    var previous: [Capacity] u8
    for count in 162
    {
        for i in Capacity
        {
            source[i]   = cast(u8) ((cast(u32) i * 37 + cast(u32) count * 11) & 0xFF)
            previous[i] = cast(u8) ((cast(u32) i * 53 + cast(u32) count * 7) & 0xFF)
        }

        source[1]   = 0
        previous[2] = 255
        source[2]   = 255
        previous[3] = 0

        var expectedNone, expectedUp: s32
        for i in count
        {
            let none = source[1 + i]
            let up   = cast #bit(u8) (none - #wrap previous[2 + i])
            expectedNone += 128 - Math.abs(cast(s32) none - 128)
            expectedUp   += 128 - Math.abs(cast(s32) up - 128)
        }

        Swag.assert(Png.filterSumIndependent(&source[1], &previous[2], count, false) == expectedNone)
        Swag.assert(Png.filterSumIndependent(&source[1], &previous[2], count, true) == expectedUp)
    }
}

func assertPackedPngExpansion(bitDepth, multiplier: u8, sampleCount: u64)
{
    const Capacity = 160
    let samplesPerByte = 8 / bitDepth
    let packedCount    = (sampleCount + samplesPerByte - 1) / samplesPerByte
    let sampleMask     = cast(u8) ((1'u32 << bitDepth) - 1)
    var packed:   [Capacity] u8
    var actual:   [Capacity] u8
    var expected: [Capacity] u8
    for i in Capacity
    {
        packed[i]   = cast(u8) ((cast(u32) i * 41 + cast(u32) sampleCount * 13 + bitDepth) & 0xFF)
        actual[i]   = 0xA5
        expected[i] = 0xA5
    }

    for i in sampleCount
    {
        let shift = 8 - bitDepth * cast(u8) (i % samplesPerByte + 1)
        let value = (packed[1 + i / samplesPerByte] >> shift) & sampleMask
        expected[3 + i] = value * multiplier
    }

    switch bitDepth
    {
    case 1:  Png.expand1Row(&packed[1], &actual[3], sampleCount, multiplier)
    case 2:  Png.expand2Row(&packed[1], &actual[3], sampleCount, multiplier)
    default: unreachable
    }

    for i in Capacity do
        Swag.assert(actual[i] == expected[i])

    for i in Capacity
    {
        actual[i]   = 0x5A
        expected[i] = 0x5A
    }

    let sourceOffset = 3 + sampleCount - packedCount
    for i in packedCount
    {
        actual[sourceOffset + i]   = packed[1 + i]
        expected[sourceOffset + i] = packed[1 + i]
    }

    for i in sampleCount
    {
        let shift = 8 - bitDepth * cast(u8) (i % samplesPerByte + 1)
        let value = (packed[1 + i / samplesPerByte] >> shift) & sampleMask
        expected[3 + i] = value * multiplier
    }

    switch bitDepth
    {
    case 1:  Png.expand1Row(&actual[sourceOffset], &actual[3], sampleCount, multiplier)
    case 2:  Png.expand2Row(&actual[sourceOffset], &actual[3], sampleCount, multiplier)
    default: unreachable
    }

    for i in Capacity do
        Swag.assert(actual[i] == expected[i])
}

#test
{
    // Palette and grayscale meanings, every vector/tail boundary, unaligned
    // pointers, sentinels, and the decoder's exact in-place expansion layout.
    let multipliers1: [2] u8 = [1, 255]
    let multipliers2: [2] u8 = [1, 85]
    for sampleCount in 130
    {
        for multiplier in multipliers1 do
            assertPackedPngExpansion(1, multiplier, sampleCount)
        for multiplier in multipliers2 do
            assertPackedPngExpansion(2, multiplier, sampleCount)
    }
}

#test
{
    // Every vector boundary, unaligned pointers, modulo-256 overflow, and the
    // untouched bytes around the destination agree with the scalar definition.
    const Capacity = 96
    var source:   [Capacity] u8
    var previous: [Capacity] u8
    var actual:   [Capacity] u8
    var expected: [Capacity] u8
    for count in 81
    {
        for i in Capacity
        {
            source[i]   = cast(u8) ((cast(u32) i * 17 + cast(u32) count * 3) & 0xFF)
            previous[i] = cast(u8) ((cast(u32) i * 29 + cast(u32) count * 5) & 0xFF)
            actual[i]   = 0xA5
            expected[i] = 0xA5
        }

        source[1]   = 255
        previous[2] = 255

        for i in count do
            expected[3 + i] = cast(u8) ((cast(u16) source[1 + i] + previous[2 + i]) & 0xFF)
        Png.defilterUpRow(&source[1], &previous[2], &actual[3], count)
        for i in Capacity do
            Swag.assert(actual[i] == expected[i])
    }
}

#test
{
    // Both PNG meanings of a nibble, every vector/tail boundary, and the real
    // in-place expansion layout agree with a non-overlapping scalar oracle.
    const Capacity = 80
    let multipliers: [2] u8 = [1, 17]
    for multiplier in multipliers
    {
        for sampleCount in 66
        {
            let packedCount = (sampleCount + 1) / 2
            var packed:   [Capacity] u8
            var actual:   [Capacity] u8
            var expected: [Capacity] u8
            for i in Capacity
            {
                packed[i]   = cast(u8) ((cast(u32) i * 41 + cast(u32) sampleCount * 13) & 0xFF)
                actual[i]   = 0xA5
                expected[i] = 0xA5
            }

            for i in sampleCount
            {
                let nibble = i % 2 ? packed[1 + i / 2] & 15 : packed[1 + i / 2] >> 4
                expected[3 + i] = nibble * multiplier
            }

            Png.expand4Row(&packed[1], &actual[3], sampleCount, multiplier)
            for i in Capacity do
                Swag.assert(actual[i] == expected[i])

            for i in Capacity
            {
                actual[i]   = 0x5A
                expected[i] = 0x5A
            }

            let sourceOffset = 3 + sampleCount - packedCount
            for i in packedCount
            {
                actual[sourceOffset + i]   = packed[1 + i]
                expected[sourceOffset + i] = packed[1 + i]
            }

            for i in sampleCount
            {
                let nibble = i % 2 ? packed[1 + i / 2] & 15 : packed[1 + i / 2] >> 4
                expected[3 + i] = nibble * multiplier
            }

            Png.expand4Row(&actual[sourceOffset], &actual[3], sampleCount, multiplier)
            for i in Capacity do
                Swag.assert(actual[i] == expected[i])
        }
    }
}

#test
{
    // Enumerate every 16-bit sample exactly once, then add an odd tail pixel.
    // Offsets and sentinels also exercise unaligned loads and the bounded store.
    const ValueCount = 65536
    const Pixels     = ValueCount / 4 + 1
    var source:   Array'u8
    var actual:   Array'u8
    var expected: Array'u8
    source.resize(1 + Pixels * 8)
    actual.resize(3 + Pixels * 4 + 1)
    expected.resize(actual.count)
    for i in actual.count
    {
        actual[i]   = 0xA5
        expected[i] = 0xA5
    }

    for channel in Pixels * 4
    {
        let value = cast(u16) (channel & 0xFFFF)
        source[1 + 2 * channel]     = cast(u8) (value >> 8)
        source[1 + 2 * channel + 1] = cast(u8) (value & 0xFF)
        expected[3 + channel]       = cast(u8) ((cast(u32) value + 128) / 257)
    }

    Png.reduce16Samples(source.buffer! + 1, actual.buffer! + 3, Pixels * 4)
    for i in actual.count do
        Swag.assert(actual[i] == expected[i])
}

#test
{
    // The encoder's inverse operation has the same vector and tail boundaries,
    // but wraps subtraction in the other direction.
    const Capacity = 96
    var source:   [Capacity] u8
    var previous: [Capacity] u8
    var actual:   [Capacity] u8
    var expected: [Capacity] u8
    for count in 81
    {
        for i in Capacity
        {
            source[i]   = cast(u8) ((cast(u32) i * 31 + cast(u32) count * 7) & 0xFF)
            previous[i] = cast(u8) ((cast(u32) i * 19 + cast(u32) count * 11) & 0xFF)
            actual[i]   = 0x5A
            expected[i] = 0x5A
        }

        source[1]   = 0
        previous[2] = 255

        for i in count do
            expected[3 + i] = cast #bit(u8) (source[1 + i] - #wrap previous[2 + i])
        Png.filterUpRow(&source[1], &previous[2], &actual[3], count)
        for i in Capacity do
            Swag.assert(actual[i] == expected[i])
    }
}

func addPngU16Be(result: *ConcatBuffer, value: u16)
{
    result.addNative(cast(u8) ((value >> 8) & 0xFF))
    result.addNative(cast(u8) (value & 0xFF))
}

func addPngU32Be(result: *ConcatBuffer, value: u32)
{
    result.addNative(cast(u8) ((value >> 24) & 0xFF))
    result.addNative(cast(u8) ((value >> 16) & 0xFF))
    result.addNative(cast(u8) ((value >> 8) & 0xFF))
    result.addNative(cast(u8) (value & 0xFF))
}

func addPngChunk(result: *ConcatBuffer, chunkType: string, data: const [..] u8)
{
    Swag.assert(chunkType.count == 4)
    addPngU32Be(result, cast(u32) data.count)
    result.addBytes(chunkType)
    result.addBytes(data)

    var crc: Hash.Crc32
    crc.update(chunkType)
    crc.update(data)
    addPngU32Be(result, crc.value())
}

func addPngSignature(result: *ConcatBuffer)
{
    const signature: [8] u8 = [137, 80, 78, 71, 13, 10, 26, 10]
    result.addBytes(signature)
}

func addPngHeader(result: *ConcatBuffer, width, height: u32, bitDepth, colorType: u8)
{
    var ihdr: ConcatBuffer
    addPngU32Be(&ihdr, width)
    addPngU32Be(&ihdr, height)
    ihdr.addNative(bitDepth)
    ihdr.addNative(colorType)
    ihdr.addNative(0'u8)
    ihdr.addNative(0'u8)
    ihdr.addNative(0'u8)
    addPngChunk(result, "IHDR", nnBytes(ihdr.toSlice()))
}

func addPngImageData(result: *ConcatBuffer, raw: const [..] u8)
{
    var zlib: Compress.ZLib
    let compressed = expect zlib.compress(raw, .Default)
    addPngChunk(result, "IDAT", nnBytes(compressed.toSlice()))
}

func buildPalettedPng(width: u32, transparency = true)->Array'u8
{
    const palette: [9] u8 = [1, 2, 3, 10, 20, 30, 200, 150, 100]
    const alpha:   [2] u8 = [4, 40]

    var raw: ConcatBuffer
    raw.addNative(0'u8)
    for i in width do
        raw.addNative(cast(u8) (i % 3))

    var result: ConcatBuffer
    addPngSignature(&result)
    addPngHeader(&result, width, 1, 8, 3)
    addPngChunk(&result, "PLTE", palette)
    if transparency do
        addPngChunk(&result, "tRNS", alpha)
    addPngImageData(&result, nnBytes(raw.toSlice()))
    addPngChunk(&result, "IEND", "")
    return cbToArray(&result)
}

func buildGrayscalePng(width: u32)->Array'u8
{
    var raw: ConcatBuffer
    raw.addNative(0'u8)
    for i in width do
        raw.addNative(cast(u8) (i & 0xFF))
    raw.makeLinear()

    var result: ConcatBuffer
    addPngSignature(&result)
    addPngHeader(&result, width, 1, 8, 0)
    addPngImageData(&result, nnBytes(raw.toSlice()))
    addPngChunk(&result, "IEND", "")
    return cbToArray(&result)
}

func buildGrayscaleTransparencyPng(width: u32, key: u8)->Array'u8
{
    var raw: ConcatBuffer
    raw.addNative(0'u8)
    for i in width do
        raw.addNative(cast(u8) (i & 0xFF))
    raw.makeLinear()

    let transparency: [2] u8 = [0, key]
    var result:       ConcatBuffer
    addPngSignature(&result)
    addPngHeader(&result, width, 1, 8, 0)
    addPngChunk(&result, "tRNS", transparency)
    addPngImageData(&result, nnBytes(raw.toSlice()))
    addPngChunk(&result, "IEND", "")
    return cbToArray(&result)
}

func buildGrayscaleAlphaPng(width: u32)->Array'u8
{
    var raw: ConcatBuffer
    raw.addNative(0'u8)
    for i in width
    {
        raw.addNative(cast(u8) (i & 0xFF))
        raw.addNative(cast(u8) (255 - (i & 0xFF)))
    }

    raw.makeLinear()

    var result: ConcatBuffer
    addPngSignature(&result)
    addPngHeader(&result, width, 1, 8, 4)
    addPngImageData(&result, nnBytes(raw.toSlice()))
    addPngChunk(&result, "IEND", "")
    return cbToArray(&result)
}

func buildRgbTransparencyPng(width: u32)->Array'u8
{
    const KeyR = 37'u8
    const KeyG = 91'u8
    const KeyB = 173'u8
    var raw: ConcatBuffer
    raw.addNative(0'u8)
    for i in width
    {
        let matches = i == 17 or i + 1 == width
        raw.addNative(matches ? KeyR : 1'u8)
        raw.addNative(matches ? KeyG : 2'u8)
        raw.addNative(matches ? KeyB : 3'u8)
    }

    raw.makeLinear()

    const transparency: [6] u8 = [0, KeyR, 0, KeyG, 0, KeyB]
    var result: ConcatBuffer
    addPngSignature(&result)
    addPngHeader(&result, width, 1, 8, 2)
    addPngChunk(&result, "tRNS", transparency)
    addPngImageData(&result, nnBytes(raw.toSlice()))
    addPngChunk(&result, "IEND", "")
    return cbToArray(&result)
}

func assertPngDecodeFails(fileName: string, encoded: *ConcatBuffer)
{
    let bytes = cbToArray(encoded)
    var image: Image
    image = catch Image.decode(fileName, nnBytes(bytes.toSlice()), {}) as decodeError
    Swag.assert(decodeError != null)
}

func buildPng16(width, height: s32, colorType: u8, interlace: bool, samples: const [..] u16, transparency: #null const [..] u16 = null)->Array'u8
{
    var channels: s32
    switch colorType
    {
    case 0:  channels = 1
    case 2:  channels = 3
    case 4:  channels = 2
    case 6:  channels = 4
    default: unreachable
    }

    Swag.assert(samples.count == cast(u64) width * cast(u64) height * cast(u64) channels)

    var raw: ConcatBuffer
    if !interlace
    {
        for y in height
        {
            raw.addNative(0'u8)
            for x in width
            {
                let pixel = cast(u64) (y * width + x) * cast(u64) channels
                for c in channels do
                    addPngU16Be(&raw, samples[pixel + c])
            }
        }
    }
    else
    {
        let startX: [7] s32 = [0, 4, 0, 2, 0, 1, 0]
        let startY: [7] s32 = [0, 0, 4, 0, 2, 0, 1]
        let stepX:  [7] s32 = [8, 8, 4, 4, 2, 2, 1]
        let stepY:  [7] s32 = [8, 8, 8, 4, 4, 2, 2]

        for pass in 7
        {
            if startX[pass] >= width or startY[pass] >= height do
                continue

            for var y = startY[pass]; y < height; y += stepY[pass]
            {
                raw.addNative(0'u8)
                for var x = startX[pass]; x < width; x += stepX[pass]
                {
                    let pixel = cast(u64) (y * width + x) * cast(u64) channels
                    for c in channels do
                        addPngU16Be(&raw, samples[pixel + c])
                }
            }
        }
    }

    var zlib:   Compress.ZLib
    let compressed = expect zlib.compress(nnBytes(raw.toSlice()), .Default)
    var result: ConcatBuffer
    addPngSignature(&result)

    var ihdr: ConcatBuffer
    addPngU32Be(&ihdr, cast(u32) width)
    addPngU32Be(&ihdr, cast(u32) height)
    ihdr.addNative(16'u8)
    ihdr.addNative(colorType)
    ihdr.addNative(0'u8)
    ihdr.addNative(0'u8)
    ihdr.addNative(interlace ? 1'u8 : 0'u8)
    addPngChunk(&result, "IHDR", nnBytes(ihdr.toSlice()))

    if transparency != null
    {
        var trns: ConcatBuffer
        for value in transparency! do
            addPngU16Be(&trns, value)
        addPngChunk(&result, "tRNS", nnBytes(trns.toSlice()))
    }

    addPngChunk(&result, "IDAT", nnBytes(compressed.toSlice()))
    addPngChunk(&result, "IEND", "")
    return cbToArray(&result)
}

// Reject structural errors before reading pixels or indexing palette data.
#test
{
    const trueColorRow: [4] u8 = [0, 10, 20, 30]
    const indexedRow:   [2] u8 = [0, 0]
    const palette:      [3] u8 = [10, 20, 30]
    const alpha:        [1] u8 = [127]

    var shortHeader: ConcatBuffer
    addPngSignature(&shortHeader)
    var shortIHDR: [12] u8
    addPngChunk(&shortHeader, "IHDR", shortIHDR)
    addPngChunk(&shortHeader, "IEND", "")
    assertPngDecodeFails("short-ihdr.png", &shortHeader)

    var truncatedChecksum: ConcatBuffer
    addPngSignature(&truncatedChecksum)
    addPngHeader(&truncatedChecksum, 1, 1, 8, 2)
    addPngU32Be(&truncatedChecksum, 1)
    truncatedChecksum.addBytes("IDAT")
    truncatedChecksum.addNative(0'u8)
    assertPngDecodeFails("truncated-checksum.png", &truncatedChecksum)

    var hugeImage: ConcatBuffer
    addPngSignature(&hugeImage)
    addPngHeader(&hugeImage, 0xFFFFFFFF, 1, 8, 2)
    addPngImageData(&hugeImage, trueColorRow)
    addPngChunk(&hugeImage, "IEND", "")
    assertPngDecodeFails("huge.png", &hugeImage)

    var unknownCritical: ConcatBuffer
    addPngSignature(&unknownCritical)
    addPngHeader(&unknownCritical, 1, 1, 8, 2)
    addPngChunk(&unknownCritical, "ABCD", "")
    addPngImageData(&unknownCritical, trueColorRow)
    addPngChunk(&unknownCritical, "IEND", "")
    assertPngDecodeFails("unknown-critical.png", &unknownCritical)

    var transparencyBeforePalette: ConcatBuffer
    addPngSignature(&transparencyBeforePalette)
    addPngHeader(&transparencyBeforePalette, 1, 1, 1, 3)
    addPngChunk(&transparencyBeforePalette, "tRNS", alpha)
    addPngChunk(&transparencyBeforePalette, "PLTE", palette)
    addPngImageData(&transparencyBeforePalette, indexedRow)
    addPngChunk(&transparencyBeforePalette, "IEND", "")
    assertPngDecodeFails("trns-before-plte.png", &transparencyBeforePalette)

    var duplicateTransparency: ConcatBuffer
    addPngSignature(&duplicateTransparency)
    addPngHeader(&duplicateTransparency, 1, 1, 1, 3)
    addPngChunk(&duplicateTransparency, "PLTE", palette)
    addPngChunk(&duplicateTransparency, "tRNS", alpha)
    addPngChunk(&duplicateTransparency, "tRNS", alpha)
    addPngImageData(&duplicateTransparency, indexedRow)
    addPngChunk(&duplicateTransparency, "IEND", "")
    assertPngDecodeFails("duplicate-trns.png", &duplicateTransparency)

    var emptyPalette: ConcatBuffer
    addPngSignature(&emptyPalette)
    addPngHeader(&emptyPalette, 1, 1, 1, 3)
    addPngChunk(&emptyPalette, "PLTE", "")
    addPngImageData(&emptyPalette, indexedRow)
    addPngChunk(&emptyPalette, "IEND", "")
    assertPngDecodeFails("empty-plte.png", &emptyPalette)

    var nonEmptyEnd: ConcatBuffer
    addPngSignature(&nonEmptyEnd)
    addPngHeader(&nonEmptyEnd, 1, 1, 8, 2)
    addPngImageData(&nonEmptyEnd, trueColorRow)
    addPngChunk(&nonEmptyEnd, "IEND", alpha)
    assertPngDecodeFails("non-empty-iend.png", &nonEmptyEnd)
}

// Decoder and encoder registries recognise PNG files.
#test
{
    Swag.assert(Image.canLoad("in.png"))
    Swag.assert(!Image.canLoad("in.pnm"))
    Swag.assert(Image.canSave("out.png"))
}

// Load real 24-bit and 32-bit PNG fixtures.
#test
{
    assertLoadedPng("rgb.png", 660, 441, .RGB8, 194'u8, 205'u8, 201'u8, 255'u8)
    assertLoadedPng("rgba.png", 660, 441, .RGBA8, 194'u8, 205'u8, 201'u8, 255'u8)
}

// Decode non-interlaced grayscale PNGs with packed bit depths.
#test
{
    assertLoadedPng("basn0g01.png", 32, 32, .Gray8, 0'u8, 0'u8, 0'u8, 255'u8)
    assertLoadedPng("basn0g02.png", 32, 32, .Gray8, 255'u8, 255'u8, 255'u8, 255'u8)
    assertLoadedPng("basn0g04.png", 32, 32, .Gray8, 119'u8, 119'u8, 119'u8, 255'u8)
    assertLoadedPng("basn4a08.png", 32, 32, .GrayAlpha8, 0'u8, 0'u8, 0'u8, 0'u8)
}

// Grayscale RGB expansion preserves the final pixel on both sides of its packed-store threshold.
#test
{
    let scalarBytes = buildGrayscalePng(4095)
    let scalarImage = expect Image.decode("gray-rgb-scalar.png", nnBytes(scalarBytes.toSlice()), {})
    assertPngPixelAt(scalarImage, 0, 0, 0'u8, 0'u8, 0'u8, 255'u8)
    assertPngPixelAt(scalarImage, 4094, 0, 254'u8, 254'u8, 254'u8, 255'u8)

    let packedBytes = buildGrayscalePng(4096)
    let packedImage = expect Image.decode("gray-rgb-packed.png", nnBytes(packedBytes.toSlice()), {})
    assertPngPixelAt(packedImage, 0, 0, 0'u8, 0'u8, 0'u8, 255'u8)
    assertPngPixelAt(packedImage, 255, 0, 255'u8, 255'u8, 255'u8, 255'u8)
    assertPngPixelAt(packedImage, 256, 0, 0'u8, 0'u8, 0'u8, 255'u8)
    assertPngPixelAt(packedImage, 4095, 0, 255'u8, 255'u8, 255'u8, 255'u8)
}

// Grayscale transparency uses the unscaled 8-bit key and matches around its packed-table threshold.
#test
{
    let scalarBytes = buildGrayscaleTransparencyPng(511, 119)
    let scalarImage = expect Image.decode("gray-trns-scalar.png", nnBytes(scalarBytes.toSlice()), {})
    assertPngPixelAt(scalarImage, 119, 0, 119'u8, 119'u8, 119'u8, 0'u8)
    assertPngPixelAt(scalarImage, 120, 0, 120'u8, 120'u8, 120'u8, 255'u8)

    let packedBytes = buildGrayscaleTransparencyPng(512, 119)
    let packedImage = expect Image.decode("gray-trns-packed.png", nnBytes(packedBytes.toSlice()), {})
    assertPngPixelAt(packedImage, 119, 0, 119'u8, 119'u8, 119'u8, 0'u8)
    assertPngPixelAt(packedImage, 120, 0, 120'u8, 120'u8, 120'u8, 255'u8)
    assertPngPixelAt(packedImage, 511, 0, 255'u8, 255'u8, 255'u8, 255'u8)
}

// Grayscale-plus-alpha packing preserves both channels around its direct-store threshold.
#test
{
    let scalarBytes = buildGrayscaleAlphaPng(255)
    let scalarImage = expect Image.decode("gray-alpha-scalar.png", nnBytes(scalarBytes.toSlice()), {})
    assertPngPixelAt(scalarImage, 0, 0, 0'u8, 0'u8, 0'u8, 255'u8)
    assertPngPixelAt(scalarImage, 254, 0, 254'u8, 254'u8, 254'u8, 1'u8)

    let packedBytes = buildGrayscaleAlphaPng(256)
    let packedImage = expect Image.decode("gray-alpha-packed.png", nnBytes(packedBytes.toSlice()), {})
    assertPngPixelAt(packedImage, 0, 0, 0'u8, 0'u8, 0'u8, 255'u8)
    assertPngPixelAt(packedImage, 119, 0, 119'u8, 119'u8, 119'u8, 136'u8)
    assertPngPixelAt(packedImage, 255, 0, 255'u8, 255'u8, 255'u8, 0'u8)
}

// RGB transparency expansion preserves scalar and SIMD boundary pixels, including the tail.
#test
{
    let scalarBytes = buildRgbTransparencyPng(4095)
    let scalarImage = expect Image.decode("rgb-trns-scalar.png", nnBytes(scalarBytes.toSlice()), {})
    assertPngPixelAt(scalarImage, 0, 0, 1'u8, 2'u8, 3'u8, 255'u8)
    assertPngPixelAt(scalarImage, 17, 0, 37'u8, 91'u8, 173'u8, 0'u8)
    assertPngPixelAt(scalarImage, 4094, 0, 37'u8, 91'u8, 173'u8, 0'u8)

    let simdBytes = buildRgbTransparencyPng(4096)
    let simdImage = expect Image.decode("rgb-trns-simd.png", nnBytes(simdBytes.toSlice()), {})
    assertPngPixelAt(simdImage, 0, 0, 1'u8, 2'u8, 3'u8, 255'u8)
    assertPngPixelAt(simdImage, 17, 0, 37'u8, 91'u8, 173'u8, 0'u8)
    assertPngPixelAt(simdImage, 4095, 0, 37'u8, 91'u8, 173'u8, 0'u8)
}

// Decode Adam7-interlaced grayscale, true-color, and alpha PNGs.
#test
{
    assertLoadedPng("basi0g08.png", 32, 32, .Gray8, 28'u8, 28'u8, 28'u8, 255'u8)
    assertLoadedPng("basi2c08.png", 32, 32, .RGB8, 31'u8, 31'u8, 31'u8, 255'u8)
    assertLoadedPng("basi4a08.png", 32, 32, .GrayAlpha8, 0'u8, 0'u8, 0'u8, 0'u8)
    assertLoadedPng("basi6a08.png", 32, 32, .RGBA8, 0'u8, 32'u8, 255'u8, 0'u8)
}

// Preserve high-depth color samples, while grayscale remains in its compact native channel count.
#test
{
    var gray: Array'u16
    gray.add(0x0000)
    gray.add(0x8080)
    gray.add(0xFFFF)

    let grayPng = buildPng16(3, 1, 0, false, gray.toSlice())
    let grayImg = expect Image.decode("gray16.png", nnBytes(grayPng.toSlice()), {})
    Swag.assert(grayImg.pixelFormat == .Gray16)
    assertPngPixelAt(grayImg, 0, 0, 0'u8, 0'u8, 0'u8, 255'u8)
    assertPngPixelAt(grayImg, 1, 0, 128'u8, 128'u8, 128'u8, 255'u8)
    assertPngPixelAt(grayImg, 2, 0, 255'u8, 255'u8, 255'u8, 255'u8)

    var rgba: Array'u16
    rgba.add(0x1234)
    rgba.add(0x8080)
    rgba.add(0xFFFF)
    rgba.add(0x0101)

    let rgbaPng = buildPng16(1, 1, 6, false, rgba.toSlice())
    let rgbaImg = expect Image.decode("rgba16.png", nnBytes(rgbaPng.toSlice()), {})
    Swag.assert(rgbaImg.pixelFormat == .RGBA16)
    assertPngPixelAt(rgbaImg, 0, 0, 18'u8, 128'u8, 255'u8, 1'u8)
    let rgbaRaw = cast(const [*] u16) rgbaImg.pixels.buffer!
    Swag.assert(rgbaRaw[0] == 0x1234 and rgbaRaw[1] == 0x8080 and rgbaRaw[2] == 0xFFFF and rgbaRaw[3] == 0x0101)
}

// A 16-bit tRNS key compares the original samples before reduction to 8 bits.
#test
{
    var samples: Array'u16
    samples.add(0x1234)
    samples.add(0x5678)
    samples.add(0x9ABC)
    samples.add(0x1235)
    samples.add(0x5678)
    samples.add(0x9ABC)

    var key: Array'u16
    key.add(0x1234)
    key.add(0x5678)
    key.add(0x9ABC)

    let png = buildPng16(2, 1, 2, false, samples.toSlice(), key.toSlice())
    let img = expect Image.decode("rgb16-trns.png", nnBytes(png.toSlice()), {})
    Swag.assert(img.pixelFormat == .RGBA16)
    Swag.assert(img.pixels.buffer != null)
    let raw = cast(const [*] u16) img.pixels.buffer!
    Swag.assert(raw[3] == 0'u16)
    Swag.assert(raw[7] == 0xFFFF'u16)
}

// Decode every Adam7 pass for a 16-bit RGB image and preserve pixel placement.
#test
{
    const Width  = 5
    const Height = 5

    var samples: Array'u16
    for y in Height
    {
        for x in Width
        {
            samples.add(cast(u16) (10 + x + y * Width) * 257)
            samples.add(cast(u16) (50 + x * 2 + y) * 257)
            samples.add(cast(u16) (100 + x + y * 3) * 257)
        }
    }

    let png = buildPng16(Width, Height, 2, true, samples.toSlice())
    let img = expect Image.decode("rgb16-adam7.png", nnBytes(png.toSlice()), {})
    Swag.assert(img.pixelFormat == .RGB16)

    for y in Height
    {
        for x in Width
        {
            assertPngPixelAt(img, x, Height - y - 1, cast(u8) (10 + x + y * Width), cast(u8) (50 + x * 2 + y), cast(u8) (100 + x + y * 3), 255'u8)
        }
    }
}

// Decode palette and tRNS transparency chunks.
#test
{
    let pal = expect Image.load(getTestDataPath("paletted.png"))
    Swag.assert(pal.width == 34)
    Swag.assert(pal.height == 24)
    Swag.assert(pal.pixelFormat == .RGBA8)
    assertPngPixelAt(pal, 10, 0, 83'u8, 56'u8, 70'u8, 255'u8)

    let grayKey = expect Image.load(getTestDataPath("tbbn0g04.png"))
    Swag.assert(grayKey.pixelFormat == .GrayAlpha8)
    assertPngPixelAt(grayKey, 15, 1, 238'u8, 238'u8, 238'u8, 255'u8)

    let rgbKey = expect Image.load(getTestDataPath("tbrn2c08.png"))
    Swag.assert(rgbKey.pixelFormat == .RGBA8)
    assertPngPixelAt(rgbKey, 0, 0, 255'u8, 255'u8, 255'u8, 0'u8)
}

// Palette RGBA expansion preserves byte order and implicit opaque alpha on both sides of its packed-table threshold.
#test
{
    let scalarBytes = buildPalettedPng(511)
    let scalarImage = expect Image.decode("palette-scalar.png", nnBytes(scalarBytes.toSlice()), {})
    assertPngPixelAt(scalarImage, 0, 0, 1'u8, 2'u8, 3'u8, 4'u8)
    assertPngPixelAt(scalarImage, 1, 0, 10'u8, 20'u8, 30'u8, 40'u8)
    assertPngPixelAt(scalarImage, 2, 0, 200'u8, 150'u8, 100'u8, 255'u8)

    let packedBytes = buildPalettedPng(512)
    let packedImage = expect Image.decode("palette-packed.png", nnBytes(packedBytes.toSlice()), {})
    assertPngPixelAt(packedImage, 0, 0, 1'u8, 2'u8, 3'u8, 4'u8)
    assertPngPixelAt(packedImage, 1, 0, 10'u8, 20'u8, 30'u8, 40'u8)
    assertPngPixelAt(packedImage, 2, 0, 200'u8, 150'u8, 100'u8, 255'u8)
    assertPngPixelAt(packedImage, 511, 0, 10'u8, 20'u8, 30'u8, 40'u8)
}

// Opaque RGB palette expansion preserves three-byte packing around the overlapping-store threshold.
#test
{
    let scalarBytes = buildPalettedPng(511, false)
    let scalarImage = expect Image.decode("palette-rgb-scalar.png", nnBytes(scalarBytes.toSlice()), {})
    Swag.assert(scalarImage.pixelFormat == .RGB8)
    assertPngPixelAt(scalarImage, 0, 0, 1'u8, 2'u8, 3'u8, 255'u8)
    assertPngPixelAt(scalarImage, 1, 0, 10'u8, 20'u8, 30'u8, 255'u8)
    assertPngPixelAt(scalarImage, 2, 0, 200'u8, 150'u8, 100'u8, 255'u8)

    let packedBytes = buildPalettedPng(512, false)
    let packedImage = expect Image.decode("palette-rgb-packed.png", nnBytes(packedBytes.toSlice()), {})
    Swag.assert(packedImage.pixelFormat == .RGB8)
    assertPngPixelAt(packedImage, 0, 0, 1'u8, 2'u8, 3'u8, 255'u8)
    assertPngPixelAt(packedImage, 1, 0, 10'u8, 20'u8, 30'u8, 255'u8)
    assertPngPixelAt(packedImage, 2, 0, 200'u8, 150'u8, 100'u8, 255'u8)
    assertPngPixelAt(packedImage, 511, 0, 10'u8, 20'u8, 30'u8, 255'u8)
}

// Decode with decodePixels=false: metadata fields are populated but no pixel buffer is allocated.
#test
{
    let bytes = expect File.readAllBytes(getTestDataPath("rgb.png"))
    var opts: DecodeOptions
    opts.decodePixels = false

    let img = expect Image.decode("meta.png", bytes.toSlice(), opts)
    Swag.assert(img.width == 660)
    Swag.assert(img.height == 441)
    Swag.assert(img.pixelFormat == .RGB8)
    Swag.assert(!img.isValid())
}

// PNG text metadata must survive a normal decode with pixels enabled.
#test
{
    let path = makeTempPngPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(2, 1, .RGB8)
    fillSolidPngImage(&src, 1'u8, 2'u8, 3'u8, 255'u8)

    var md: ImageMetadata
    md.tag   = "Editor.SourceFile"
    md.value = "drawing.editor"
    src.metadata.add(md)

    expect src.save(path.toString())
    let img = expect Image.load(path.toString())
    Swag.assert(img.isValid())
    Swag.assert(img.metadata.count == 1)
    Swag.assert(img.metadata[0].isTag("Editor.SourceFile"))
    Swag.assert(cast(string) img.metadata[0].toSlice() == "drawing.editor")
}

// Invalid and truncated buffers should fail without producing an image.
#test
{
    let bad: [8] u8 = [0, 1, 2, 3, 4, 5, 6, 7]
    var img: Image
    img = catch Image.decode("bad.png", Swag.makeSlice(&bad[0], bad.count), {}) as err11
    Swag.assert(err11 != null)

    let bytes = expect File.readAllBytes(getTestDataPath("rgb.png"))
    img = catch Image.decode("truncated.png", Swag.makeSlice(bytes.buffer, 32), {}) as err13
    Swag.assert(err13 != null)
}

// Encode native grayscale, 8-bit color, and 16-bit color without widening or reducing samples.
#test
{
    var gray = Image.create(3, 2, .Gray8)
    for i in gray.byteCount do
        gray.pixels.buffer![i] = cast(u8) (i * 41)
    assertEncodedPngRoundtrip(gray, .Gray8)

    var grayAlpha = Image.create(3, 2, .GrayAlpha8)
    for i in grayAlpha.byteCount do
        grayAlpha.pixels.buffer![i] = cast(u8) (i * 19)
    assertEncodedPngRoundtrip(grayAlpha, .GrayAlpha8)

    var gray16 = Image.create(3, 2, .Gray16)
    for i in gray16.byteCount do
        gray16.pixels.buffer![i] = cast(u8) (i * 23)
    assertEncodedPngRoundtrip(gray16, .Gray16)

    var grayAlpha16 = Image.create(3, 2, .GrayAlpha16)
    for i in grayAlpha16.byteCount do
        grayAlpha16.pixels.buffer![i] = cast(u8) (i * 11)
    assertEncodedPngRoundtrip(grayAlpha16, .GrayAlpha16)

    var rgb = Image.create(2, 2, .RGB8)
    rgb.clear()
    let rgbBuf = rgb.pixels.buffer!
    rgbBuf[0]  = 10'u8
    rgbBuf[1]  = 20'u8
    rgbBuf[2]  = 30'u8
    rgbBuf[9]  = 100'u8
    rgbBuf[10] = 110'u8
    rgbBuf[11] = 120'u8
    assertEncodedPngRoundtrip(rgb, .RGB8)

    var rgba = Image.create(2, 2, .RGBA8)
    rgba.clear()
    let rgbaBuf = rgba.pixels.buffer!
    rgbaBuf[0]  = 1'u8
    rgbaBuf[1]  = 2'u8
    rgbaBuf[2]  = 3'u8
    rgbaBuf[3]  = 4'u8
    rgbaBuf[12] = 200'u8
    rgbaBuf[13] = 201'u8
    rgbaBuf[14] = 202'u8
    rgbaBuf[15] = 203'u8
    assertEncodedPngRoundtrip(rgba, .RGBA8)

    var rgb16    = Image.create(2, 2, .RGB16)
    let rgb16Buf = cast([*] u16) rgb16.pixels.buffer!
    for i in 12 do
        rgb16Buf[i] = cast(u16) (i * 5003)
    assertEncodedPngRoundtrip(rgb16, .RGB16)

    var rgba16    = Image.create(2, 2, .RGBA16)
    let rgba16Buf = cast([*] u16) rgba16.pixels.buffer!
    for i in 16 do
        rgba16Buf[i] = cast(u16) (i * 4001)
    assertEncodedPngRoundtrip(rgba16, .RGBA16)
}

// Encode BGR/BGRA source images by swapping R/B into PNG's RGB component order.
#test
{
    var bgr    = Image.create(1, 1, .BGR8)
    let bgrBuf = bgr.pixels.buffer!
    bgrBuf[0] = 30'u8
    bgrBuf[1] = 20'u8
    bgrBuf[2] = 10'u8

    let bgrEncoded = expect bgr.encode("memory.png")
    let bgrDecoded = expect Image.decode("bgr.png", nnBytes(bgrEncoded.toSlice()), {})
    Swag.assert(bgrDecoded.pixelFormat == .RGB8)
    assertPngPixelAt(bgrDecoded, 0, 0, 10'u8, 20'u8, 30'u8, 255'u8)

    var bgra    = Image.create(1, 1, .BGRA8)
    let bgraBuf = bgra.pixels.buffer!
    bgraBuf[0] = 7'u8
    bgraBuf[1] = 8'u8
    bgraBuf[2] = 9'u8
    bgraBuf[3] = 10'u8

    let bgraEncoded = expect bgra.encode("memory.png")
    let bgraDecoded = expect Image.decode("bgra.png", nnBytes(bgraEncoded.toSlice()), {})
    Swag.assert(bgraDecoded.pixelFormat == .RGBA8)
    assertPngPixelAt(bgraDecoded, 0, 0, 9'u8, 8'u8, 7'u8, 10'u8)
}

// Encode with explicit PNG options and round-trip the written bytes through the decoder.
#test
{
    let path = makeTempPngPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(3, 2, .RGB8)
    fillSolidPngImage(&src, 24'u8, 48'u8, 96'u8, 255'u8)

    var opts: Png.EncodeOptions
    opts.filtering        = false
    opts.compressionLevel = .NoCompression

    let cb = expect src.encode("memory.png", opts)
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixelFormat == .RGB8)
    Swag.assert(Memory.compare(src.pixels.buffer, img.pixels.buffer, src.pixels.count) == 0)
}

// Default options enable filtering and Deflate compression, unlike an explicit
// stored stream.
#test
{
    var src = Image.create(64, 64, .RGB8)
    fillSolidPngImage(&src, 24'u8, 48'u8, 96'u8, 255'u8)

    let compressed = expect src.encode("memory.png")
    var options: Png.EncodeOptions
    options.filtering        = false
    options.compressionLevel = .NoCompression

    let stored = expect src.encode("memory.png", options)
    Swag.assert(compressed.count() < stored.count())

    compressed.makeLinear()
    let decoded = expect Image.decode("default-options.png", nnBytes(compressed.toSlice()), {})
    Swag.assert(Memory.compare(src.pixels.buffer, decoded.pixels.buffer, src.pixels.count) == 0)
}

// Encode Adam7-interlaced RGB and BGRA images, including odd dimensions that
// exercise every pass, and round-trip them through the decoder.
#test
{
    var options: Png.EncodeOptions
    options.interlace = true

    var rgb    = Image.create(9, 7, .RGB8)
    let rgbBuf = rgb.pixels.buffer!
    for y in rgb.height
    {
        for x in rgb.width
        {
            let offset = cast(u64) (y * rgb.width + x) * 3
            rgbBuf[offset]     = cast(u8) (x * 17 + y)
            rgbBuf[offset + 1] = cast(u8) (x + y * 19)
            rgbBuf[offset + 2] = cast(u8) (x * 7 + y * 11)
        }
    }

    let cb       = expect rgb.encode("memory.png", options)
    let rgbBytes = nnBytes(cb.toSlice())
    Swag.assert(rgbBytes[28] == 1'u8)

    let decoded = expect Image.decode("adam7-rgb.png", rgbBytes, {})
    Swag.assert(decoded.pixelFormat == .RGB8)
    Swag.assert(Memory.compare(rgb.pixels.buffer, decoded.pixels.buffer, rgb.pixels.count) == 0)

    var bgra    = Image.create(9, 7, .BGRA8)
    let bgraBuf = bgra.pixels.buffer!
    for y in bgra.height
    {
        for x in bgra.width
        {
            let offset = cast(u64) (y * bgra.width + x) * 4
            bgraBuf[offset]     = cast(u8) (10 + x)
            bgraBuf[offset + 1] = cast(u8) (20 + y)
            bgraBuf[offset + 2] = cast(u8) (30 + x + y)
            bgraBuf[offset + 3] = cast(u8) (40 + x * 3 + y * 5)
        }
    }

    let bgraEncoded = expect bgra.encode("memory.png", options)
    let bgraBytes   = nnBytes(bgraEncoded.toSlice())
    Swag.assert(bgraBytes[28] == 1'u8)

    let bgraDecoded = expect Image.decode("adam7-bgra.png", bgraBytes, {})
    Swag.assert(bgraDecoded.pixelFormat == .RGBA8)
    let decodedBuf = bgraDecoded.pixels.buffer!
    for i in cast(u64) bgra.width * cast(u64) bgra.height
    {
        let offset = i * 4
        Swag.assert(decodedBuf[offset] == bgraBuf[offset + 2])
        Swag.assert(decodedBuf[offset + 1] == bgraBuf[offset + 1])
        Swag.assert(decodedBuf[offset + 2] == bgraBuf[offset])
        Swag.assert(decodedBuf[offset + 3] == bgraBuf[offset + 3])
    }
}
