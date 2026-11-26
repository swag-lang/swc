//! Format: MPEG-4 AAC Low Complexity packet decoder component.
//! Supported: 1024-sample AAC-LC access units, standard sample-rate indexes, channel configurations 1 through 6, long/short windows, TNS, intensity stereo, and perceptual noise substitution.
//! Not supported: Other AAC profiles, 960-sample frames, explicit sample rates, pulse data, gain control, core-coder dependencies, and extension flags.
//! Role: This file owns AAC syntax, scale factors, spectral decoding, stereo tools, IMDCT, overlap, and PCM output.
//
#global namespace Aac

using Core, Core.Errors, Core.Math

private const FrameSamples = 1024
private const MaxBands     = 8 * 52
private const MaxChannels  = 6

internal const MaxPacketBatchSize  = 512'u64
internal const MaxPacketBatchLanes = 4'u64
private const BatchStateCount      = 64'u64

// A nonzero lookup entry packs four biased six-bit coefficients followed by the number
// of bits consumed. Long words, and prefixes near the end of the packet, use the tree.
private const SpectralPrefixBits = 11
private const SpectralValueBias  = 16
private const SpectralValueBits  = 6
private const SpectralValueMask  = (1'u32 << SpectralValueBits) - 1
private const SpectralCountShift = 4 * SpectralValueBits

private struct BitReader
{
    data:    const [*] u8
    length:  s32
    bitPos:  s32
    overrun: bool
}

private impl BitReader
{
    func create(data: const [*] u8, length: u64)->BitReader => BitReader{data, cast(s32, length), 0, false}

    mtd const left()->s32 => .length * 8 - .bitPos

    mtd get(count: s32)->u32
    {
        let available = Math.min(count, Math.max(.left(), 0))
        var remaining = available
        var value: u32
        while remaining
        {
            let byteBits = 8 - (.bitPos & 7)
            let take     = Math.min(remaining, byteBits)
            let bits     = cast(u32, .data[.bitPos >> 3]) >> (byteBits - take)
            value     = (value << take) | (bits & ((1'u32 << take) - 1))
            .bitPos   += take
            remaining -= take
        }

        let missing = count - available
        if missing
        {
            .overrun = true
            .bitPos  += missing
            value    <<= missing
        }

        return value
    }

    mtd get1()->u32
    {
        let pos = .bitPos
        .bitPos += 1
        if pos >> 3 >= .length
        {
            .overrun = true
            return 0
        }

        return (cast(u32, .data[pos >> 3]) >> (7 - (pos & 7))) & 1
    }

    mtd readEscapeMagnitude()->s32 fail
    {
        var leading = 0's32
        while .get1() do
            leading += 1
        if leading > 11 do
            fail InvalidFormatError{"AAC escape coefficient is too large"}
        let bits = leading + 4
        return (1 << bits) + cast(s32, .get(bits))
    }

    // The caller has checked that a complete 32-bit word remains.
    mtd const peekSpectralPrefix()->u32
    {
        let word = Math.bigEndianToNative(cast(const [*] u32, .data + (.bitPos >> 3))[0])
        return (word >> (32 - SpectralPrefixBits - (.bitPos & 7))) & ((1'u32 << SpectralPrefixBits) - 1)
    }

    // The caller has checked that eight bits remain.
    mtd const peekByte()->u32
    {
        let index  = .bitPos >> 3
        let offset = .bitPos & 7
        if not offset do
            return .data[index]
        return ((cast(u32, .data[index]) << offset) & 0xFF) | (cast(u32, .data[index + 1]) >> (8 - offset))
    }
}

private const HuffPrefixBits = 8

private struct HuffPrefix
{
    next: s16
    bits: u8
}

private struct HuffTree
{
    child:    [600, 2] s32
    nodes:    s32 = 1
    prefixes: [1 << HuffPrefixBits] HuffPrefix
}

private impl HuffTree
{
    mtd reset()
    {
        .nodes = 1
        Memory.set(&.child, 0, #sizeof(.child))
    }

    mtd insert(code: u32, bitCount, leaf: s32)
    {
        var at  = 0's32
        var bit = bitCount - 1
        while bit >= 0
        {
            let branch = cast(s32, ((code >> cast(u32, bit)) & 1))
            if not bit
            {
                .child[at, branch] = ~leaf
                return
            }

            if .child[at, branch] <= 0
            {
                if .nodes >= 600 do
                    return
                .child[at, branch] = .nodes
                .child[.nodes, 0]  = 0
                .child[.nodes, 1]  = 0
                .nodes += 1
            }

            at  = .child[at, branch]
            bit -= 1
        }
    }

    mtd buildPrefixes()
    {
        for index in .prefixes.count
        {
            var next = 0's32
            for bit in HuffPrefixBits
            {
                next = .child[next, (index >> (HuffPrefixBits - 1 - bit)) & 1]
                .prefixes[index] = {cast(s16, next), cast(u8, bit + 1)}
                if next <= 0 do
                    break
            }
        }
    }

    mtd const decode(reader: *BitReader)->s32
    {
        var at   = 0's32
        var used = 0's32
        if reader.left() >= HuffPrefixBits
        {
            let prefix = .prefixes[reader.peekByte()]
            reader.bitPos += prefix.bits
            at   = prefix.next
            used = prefix.bits
            if at <= 0 do
                return ~at
        }

        for used until 24
        {
            let next = .child[at, reader.get1()]
            if next <= 0 do
                return ~next
            at = next
        }

        return -1
    }
}

private struct ImdctPlan
{
    size:    s32
    quarter: s32
    reverse: [512] u32
    fftReal: [512] f32
    fftImag: [512] f32
    twReal:  [512] f32
    twImag:  [512] f32
}

private impl ImdctPlan
{
    mtd init(size: s32)
    {
        .size    = size
        .quarter = size / 4
        let quarter = cast(u32, .quarter)
        let shift   = Swag.leadingZeros(quarter) + 1
        for i in quarter do
            .reverse[i] = Math.reverse(cast(u32, i)) >> shift

        // Each stage's adjacent twiddle factors are contiguous for two-wide loads.
        let pi        = Math.ConstF64.Pi
        var stride    = quarter / 2
        var butterfly = 1'u32
        while butterfly < quarter
        {
            for j in butterfly
            {
                let angle = 2.0 * pi * cast(f64, j * stride) / cast(f64, quarter)
                .fftReal[butterfly + j] = cast(f32, Math.cos(angle))
                .fftImag[butterfly + j] = cast(f32, Math.sin(angle))
            }

            stride    >>= 1
            butterfly <<= 1
        }

        let half = size / 2
        for i in cast(u64, .quarter)
        {
            let angle = pi * (cast(f64, i) + 0.125) / cast(f64, half)
            .twReal[i] = cast(f32, Math.cos(angle))
            .twImag[i] = -cast(f32, Math.sin(angle))
        }
    }

    mtd const run(spectrum: const [*] f64, output: [*] f32)
    {
        let half    = .size / 2
        let quarter = .quarter
        var real: [512] f32
        var imag: [512] f32
        let re      = cast([*] f32, &real[0])
        let im      = cast([*] f32, &imag[0])
        let cos     = cast(const [*] f32, &.fftReal[0])
        let sin     = cast(const [*] f32, &.fftImag[0])
        for k in cast(u64, quarter)
        {
            let a     = cast(f32, spectrum[2 * k]) * 0.5
            let b     = -cast(f32, spectrum[cast(u64, half) - 1 - 2 * k]) * 0.5
            let index = .reverse[k]
            re[index] = a * .twReal[k] + b * .twImag[k]
            im[index] = -a * .twImag[k] + b * .twReal[k]
        }

        // The first two stages have fewer than four butterflies per group.
        for stage in 2
        {
            let span   = 1'u32 << stage
            let length = 2 * span
            for group in cast(u32, quarter) / length
            {
                let base = group * length
                for j in span
                {
                    let a  = base + j
                    let b  = a + span
                    let xr = re[b] * cos[span + j] - im[b] * sin[span + j]
                    let xi = re[b] * sin[span + j] + im[b] * cos[span + j]
                    re[b] = re[a] - xr
                    im[b] = im[a] - xi
                    re[a] += xr
                    im[a] += xi
                }
            }
        }

        var butterfly = 4'u32
        while butterfly < quarter
        {
            let length = 2 * butterfly
            var base   = 0'u32
            while base < quarter
            {
                var j = 0'u32
                while j < butterfly
                {
                    let a  = base + j
                    let b  = a + butterfly
                    let wr = Simd.load(cos + butterfly + j)
                    let wi = Simd.load(sin + butterfly + j)
                    let ar = Simd.load(re + a)
                    let ai = Simd.load(im + a)
                    let br = Simd.load(re + b)
                    let bi = Simd.load(im + b)
                    let xr = br * wr - bi * wi
                    let xi = br * wi + bi * wr
                    Simd.store(re + b, ar - xr)
                    Simd.store(im + b, ai - xi)
                    Simd.store(re + a, ar + xr)
                    Simd.store(im + a, ai + xi)
                    j += 4
                }

                base += length
            }

            butterfly = length
        }

        let inv   = cast(f32, (1.0 / cast(f64, quarter)))
        let rotRe = cast(const [*] f32, &.twReal[0])
        let rotIm = cast(const [*] f32, &.twImag[0])
        let span  = cast(u64, quarter)
        for group in span / 4
        {
            let i       = 4 * group
            let c       = Simd.load(rotRe + i)
            let sn      = Simd.load(rotIm + i)
            let r       = Simd.load(re + i) * inv
            let imValue = Simd.load(im + i) * inv
            Simd.store(re + i, r * c + imValue * sn)
            Simd.store(im + i, imValue * c - r * sn)
        }

        // Each FFT half supplies four even lanes and four reflected odd lanes.
        const FirstTwo = cast(Simd.U32x4, [0'u32, 7, 1, 6])
        const LastTwo  = cast(Simd.U32x4, [2'u32, 5, 3, 4])
        for group in span / 8
        {
            let i             = 4 * group
            let j             = i + span / 2
            let lowMirror     = span / 2 - 4 - i
            let highMirror    = span - 4 - i
            let lowRe         = Simd.load(re + i)
            let lowIm         = Simd.load(im + i)
            let highRe        = Simd.load(re + j)
            let highIm        = Simd.load(im + j)
            let reverseLowRe  = Simd.load(re + lowMirror)
            let reverseLowIm  = Simd.load(im + lowMirror)
            let reverseHighRe = Simd.load(re + highMirror)
            let reverseHighIm = Simd.load(im + highMirror)
            let first         = output + 2 * i
            let second        = first + span
            let third         = second + span
            let fourth        = third + span
            Simd.store(first, Simd.permute2(highRe, reverseLowIm, FirstTwo))
            Simd.store(first + 4, Simd.permute2(highRe, reverseLowIm, LastTwo))
            Simd.store(second, -Simd.permute2(lowIm, reverseHighRe, FirstTwo))
            Simd.store(second + 4, -Simd.permute2(lowIm, reverseHighRe, LastTwo))
            Simd.store(third, -Simd.permute2(highIm, reverseLowRe, FirstTwo))
            Simd.store(third + 4, -Simd.permute2(highIm, reverseLowRe, LastTwo))
            Simd.store(fourth, -Simd.permute2(lowRe, reverseHighIm, FirstTwo))
            Simd.store(fourth + 4, -Simd.permute2(lowRe, reverseHighIm, LastTwo))
        }
    }
}

private var g_SpectralTrees:     [11] HuffTree
private var g_SpectralPrefixes:  [11, 1 << SpectralPrefixBits] u32
private var g_SignedPowers:      [2 * SpectralValueBias + 1] f64
private var g_SpectralValues:    [11, 289, 4] s32
private var g_ScaleTree:         HuffTree
private var g_ImdctLong:         ImdctPlan
private var g_ImdctShort:        ImdctPlan
private var g_LongWindows:       [2, 1024] f32
private var g_TransitionWindows: [2, 1024] f32
private var g_ShortWindows:      [2, 128] f32
private var g_QuantizedPowers:   [1024] f64

private const BandGainBias = 256
private var g_BandGains: [2 * BandGainBias] f64

private func bandGain(scale: s32)->f64
{
    let index = scale + BandGainBias
    return index >= 0 and index < g_BandGains.count ? g_BandGains[index] : Math.pow(2.0, 0.25 * cast(f64, scale))
}

private func requantize(value: s32, gain: f64)->f64
{
    let magnitude = Math.abs(value)
    let power     = magnitude < g_QuantizedPowers.count ? g_QuantizedPowers[magnitude] :
                    Math.pow(cast(f64, magnitude), 4.0 / 3.0)
    return (value < 0 ? -power : power) * gain
}

// A primary entry contains the entire tuple and consumes the codeword and its sign bits.
private func buildSpectralPrefixes(book: u64, code: u32, bits: u8, values: const *[4] s32)
{
    let dimension = BookDim[book]
    let signed    = BookSigned[book] != 0
    var signCount = 0'u32
    if not signed
    {
        for item in dimension where values[][item] do
            signCount += 1
    }

    let bitCount = cast(u32, bits) + signCount
    if bitCount > SpectralPrefixBits do
        return

    let remaining = SpectralPrefixBits - bitCount
    for signs in 1'u32 << signCount
    {
        var at     = signCount
        var packed = bitCount << SpectralCountShift
        for item in dimension
        {
            var coefficient = values[][item]
            if not signed and coefficient
            {
                at -= 1
                if (signs >> at) & 1 do
                    coefficient = -coefficient
            }

            packed |= cast(u32, coefficient + SpectralValueBias) << (item * SpectralValueBits)
        }

        let first = ((code << signCount) | cast(u32, signs)) << remaining
        for suffix in 1'u32 << remaining do
            g_SpectralPrefixes[book, first + suffix] = packed
    }
}

private func initializeTables()
{
    for book in 11
    {
        g_SpectralTrees[book].reset()
        let bits      = specBits(cast(u32, book))
        let codes     = specCodes(cast(u32, book))
        let dimension = cast(s32, BookDim[book])
        let largest   = cast(s32, BookLav[book])
        let signed    = BookSigned[book] != 0
        let bias      = signed ? largest : 0
        let radix     = signed ? 2 * largest + 1 : largest + 1
        for index in cast(u64, BookSize[book]) where bits[index] != 0
        {
            g_SpectralTrees[book].insert(codes[index], bits[index], cast(s32, index))

            var packed = cast(s32, index)
            for component in dimension
            {
                g_SpectralValues[book, index, dimension - 1 - component] = packed % radix - bias
                packed /= radix
            }

            buildSpectralPrefixes(book, codes[index], bits[index], &g_SpectralValues[book, index])
        }

        g_SpectralTrees[book].buildPrefixes()
    }

    g_ScaleTree.reset()
    for index in 121 where ScfBits[index] != 0 do
        g_ScaleTree.insert(ScfCodes[index], ScfBits[index], cast(s32, index))
    g_ScaleTree.buildPrefixes()

    for magnitude in g_QuantizedPowers.count do
        g_QuantizedPowers[magnitude] = Math.pow(cast(f64, magnitude), 4.0 / 3.0)

    for value in g_SignedPowers.count do
        g_SignedPowers[value] = requantize(cast(s32, value) - SpectralValueBias, 1.0)

    for index in g_BandGains.count do
        g_BandGains[index] = Math.pow(2.0, 0.25 * cast(f64, (cast(s32, index) - BandGainBias)))

    g_ImdctLong.init(2048)
    g_ImdctShort.init(256)

    for index in 1024 do
        g_LongWindows[0, index] = cast(f32, Math.sin(Math.ConstF64.Pi / 2048.0 * (cast(f64, index) + 0.5)))
    for index in 128 do
        g_ShortWindows[0, index] = cast(f32, Math.sin(Math.ConstF64.Pi / 256.0 * (cast(f64, index) + 0.5)))
    initializeKbdWindow(&g_LongWindows[1, 0], 4.0, 1024)
    initializeKbdWindow(&g_ShortWindows[1, 0], 6.0, 128)

    // The long-stop left window is also the long-start right window in reverse.
    for shape in 2
    {
        for index in 128 do
            g_TransitionWindows[shape, 448 + index] = g_ShortWindows[shape, index]
        for index in 576 until 1024 do
            g_TransitionWindows[shape, index] = 1
    }
}

private func initializeKbdWindow(window: [*] f32, alpha: f64, half: s32)
{
    var cumulative: [1024] f64
    let scaled = alpha * Math.ConstF64.Pi / cast(f64, half)
    let factor = scaled * scaled
    var sum    = 0'f64
    for index in cast(u64, half)
    {
        let value = cast(f64, index) * cast(f64, (half - cast(s32, index))) * factor
        var b     = 1'f64
        var step  = 50's32
        while step > 0
        {
            b    = b * value / cast(f64, (step * step)) + 1.0
            step -= 1
        }

        sum += b
        cumulative[index] = sum
    }

    sum += 1.0
    for index in cast(u64, half) do
        window[index] = cast(f32, Math.sqrt(cumulative[index] / sum))
}

private struct Ics
{
    windowSequence:  s32
    windowShape:     s32
    maxSfb:          s32
    numWindows:      s32
    numWindowGroups: s32
    groupLength:     [8] s32
}

private struct TnsFilter
{
    order:     s32
    length:    s32
    direction: s32
    lpc:       [13] f64
}

private struct AacCodec
{
    using base: Codec

    sampleRateIndex: s32
    channels:        s32
    ics:             [MaxChannels] Ics
    books:           [MaxChannels, MaxBands] s32
    scaleFactors:    [MaxChannels, MaxBands] s32
    coefficients:    [MaxChannels, FrameSamples] f64
    tns:             [MaxChannels, 8, 3] TnsFilter
    tnsFilterCount:  [MaxChannels, 8] s32
    pairStart:       [MaxChannels] bool
    usesMs:          [MaxChannels] bool
    msUsed:          [MaxChannels, MaxBands] u8
    overlap:         [MaxChannels, FrameSamples] f32
    previousShape:   [MaxChannels] s32
    pnsState:        u32
    noiseSamples:    u32
}

private impl AacCodec
{
    mtd resetState()
    {
        Memory.set(&.overlap, 0, #sizeof(.overlap))
        Memory.set(&.previousShape, 0, #sizeof(.previousShape))
        .pnsState = 0x01234567
    }

    mtd parseIcsInfo(reader: *BitReader, value: *Ics) fail
    {
        discard reader.get1()
        value.windowSequence = cast(s32, reader.get(2))
        value.windowShape    = cast(s32, reader.get1())
        if value.windowSequence == 2
        {
            value.maxSfb = cast(s32, reader.get(4))
            let grouping = reader.get(7)
            value.numWindows      = 8
            value.numWindowGroups = 1
            value.groupLength[0]  = 1
            for window in 1 until 8
            {
                let shares = (grouping >> cast(u32, (7 - window))) & 1
                if shares
                {
                    value.groupLength[value.numWindowGroups - 1] += 1
                }
                else
                {
                    value.groupLength[value.numWindowGroups] = 1
                    value.numWindowGroups += 1
                }
            }

            if value.maxSfb > NumSwbShort[.sampleRateIndex] do
                fail InvalidFormatError{"AAC short window exceeds its scalefactor bands"}
        }
        else
        {
            value.maxSfb          = cast(s32, reader.get(6))
            value.numWindows      = 1
            value.numWindowGroups = 1
            value.groupLength[0]  = 1
            if reader.get1() do
                fail UnsupportedFormatError{"AAC prediction is not supported by the Low Complexity profile"}
            if value.maxSfb > NumSwbLong[.sampleRateIndex] do
                fail InvalidFormatError{"AAC long window exceeds its scalefactor bands"}
        }
    }

    mtd randomNoise()->f64
    {
        .pnsState = nextNoiseState(.pnsState)
        return cast(f64, (.pnsState >> 8)) * (2.0 / 16777216.0) - 1.0
    }

    mtd synthesizeNoiseBand(channel, scale, first, last: s32)
    {
        var energy = 0'f64
        for index in first until last
        {
            let noise = .randomNoise()
            .coefficients[channel, index] = noise
            energy += noise * noise
        }

        let width  = last - first
        let target = bandGain(scale - 100)
        let norm   = energy > 0 ? target * Math.sqrt(cast(f64, width) / energy) : 0.0
        for index in first until last do
            .coefficients[channel, index] *= norm
    }

    mtd synthesizeNoise(channel: s32)
    {
        let value = &.ics[channel]
        if value.windowSequence == 2
        {
            let offsets   = swbShort(.sampleRateIndex)
            var bandIndex = 0's32
            var line      = 0's32
            for group in value.numWindowGroups
            {
                for band in value.maxSfb
                {
                    let width = cast(s32, (offsets[band + 1] - offsets[band])) * value.groupLength[group]
                    if .books[channel, bandIndex] == 13 do
                        .synthesizeNoiseBand(channel, .scaleFactors[channel, bandIndex], line, line + width)
                    line      += width
                    bandIndex += 1
                }
            }
        }
        else
        {
            let offsets = swbLong(.sampleRateIndex)
            for band in value.maxSfb where .books[channel, band] == 13 do
                .synthesizeNoiseBand(channel, .scaleFactors[channel, band], offsets[band], offsets[band + 1])
        }
    }

    mtd deinterleaveShort(channel: s32)
    {
        let value = &.ics[channel]
        if value.windowSequence != 2 do
            return
        var natural: [FrameSamples] f64
        let offsets    = swbShort(.sampleRateIndex)
        var line       = 0's32
        var windowBase = 0's32
        for group in value.numWindowGroups
        {
            for band in value.maxSfb
            {
                for window in value.groupLength[group]
                {
                    let destination = 128 * (windowBase + window)
                    for index in offsets[band] until offsets[band + 1]
                    {
                        natural[destination + index] = .coefficients[channel, line]
                        line += 1
                    }
                }
            }

            windowBase += value.groupLength[group]
        }

        Memory.copy(&.coefficients[channel, 0], &natural, #sizeof(natural))
    }

    mtd applyTns(channel: s32)
    {
        let value    = &.ics[channel]
        let isShort  = value.windowSequence == 2
        let offsets  = isShort ? swbShort(.sampleRateIndex) : swbLong(.sampleRateIndex)
        let numBands = isShort ? cast(s32, NumSwbShort[.sampleRateIndex]) : cast(s32, NumSwbLong[.sampleRateIndex])
        var maximum  = isShort ? cast(s32, TnsMaxBandsShort[.sampleRateIndex]) :
                       cast(s32, TnsMaxBandsLong[.sampleRateIndex])
        maximum = Math.min(maximum, value.maxSfb, numBands)
        let windowCount = isShort ? 8 : 1
        for window in windowCount
        {
            var bottom = numBands
            let base   = isShort ? 128 * window : 0
            for filterIndex in .tnsFilterCount[channel, window]
            {
                let filter = &.tns[channel, window, filterIndex]
                let top    = bottom
                bottom = Math.max(top - filter.length, 0)
                if not filter.order do
                    continue
                let start = cast(s32, offsets[Math.min(bottom, maximum)])
                let end   = cast(s32, offsets[Math.min(top, maximum)])
                if end <= start do
                    continue

                let increment = filter.direction ? -1 : 1
                var line      = filter.direction ? end - 1 : start
                var history: [13] f64
                for sample in end - start
                {
                    var valueAtLine  = .coefficients[channel, base + line]
                    let historyCount = Math.min(sample, filter.order)
                    for order in 1 until historyCount + 1 do
                        valueAtLine -= filter.lpc[order] * history[order - 1]
                    var order = filter.order - 1
                    while order > 0
                    {
                        history[order] = history[order - 1]
                        order -= 1
                    }

                    history[0] = valueAtLine
                    .coefficients[channel, base + line] = valueAtLine
                    line       += increment
                }
            }
        }
    }

    mtd imdctChannel(channel: s32, output: [*] f32)
    {
        let value         = &.ics[channel]
        let currentShape  = value.windowShape
        let previousShape = .previousShape[channel]

        if value.windowSequence != 2
        {
            var transformed: [2048] f32
            g_ImdctLong.run(&.coefficients[channel, 0], &transformed)
            let leftWindow = value.windowSequence == 3 ? cast(const [*] f32, &g_TransitionWindows[previousShape, 0]) :
                             cast(const [*] f32, &g_LongWindows[previousShape, 0])
            let rightWindow = value.windowSequence == 1 ? cast(const [*] f32, &g_TransitionWindows[currentShape, 0]) :
                              cast(const [*] f32, &g_LongWindows[currentShape, 0])
            let raw     = cast(const [*] f32, &transformed[0])
            let overlap = cast([*] f32, &.overlap[channel, 0])
            const Reverse = cast(Simd.U32x4, [3'u32, 2, 1, 0])
            for group in FrameSamples / 4
            {
                let index    = 4 * group
                let left     = Simd.load(raw + index) * Simd.load(leftWindow + index)
                let right    = Simd.load(raw + FrameSamples + index)
                let reversed = Simd.load(rightWindow + FrameSamples - index - 4)
                let tail     = Simd.permute(reversed, Reverse)
                Simd.store(output + index, left + Simd.load(overlap + index))
                Simd.store(overlap + index, right * tail)
            }
        }
        else
        {
            var time: [2048] f32
            for window in 8
            {
                var transformed: [256] f32
                g_ImdctShort.run(&.coefficients[channel, 128 * window], &transformed)
                let leftShape = window == 0 ? previousShape : currentShape
                let base      = 448 + 128 * window
                for index in 128
                {
                    time[base + index]       += transformed[index] * g_ShortWindows[leftShape, index]
                    time[base + 128 + index] += transformed[128 + index] * g_ShortWindows[currentShape, 127 - index]
                }
            }

            for index in FrameSamples
            {
                output[index] = (time[index] + .overlap[channel, index])
                .overlap[channel, index] = time[FrameSamples + index]
            }
        }

        .previousShape[channel] = currentShape
    }

    mtd decodeScaleFactors(reader: *BitReader, channel, bandCount, globalGain: s32) fail
    {
        var scale       = globalGain
        var intensity   = 0's32
        var noiseEnergy = globalGain - 90
        var firstNoise  = true
        for band in bandCount
        {
            let book = .books[channel, band]
            if not book
            {
                .scaleFactors[channel, band] = 0
                continue
            }

            if book == 14 or book == 15
            {
                let index = g_ScaleTree.decode(reader)
                if index < 0 do
                    fail InvalidFormatError{"AAC intensity scalefactor code is invalid"}
                intensity += index - 60
                .scaleFactors[channel, band] = intensity
            }
            elif book == 13
            {
                if firstNoise
                {
                    firstNoise  = false
                    noiseEnergy += cast(s32, reader.get(9)) - 256
                }
                else
                {
                    let index = g_ScaleTree.decode(reader)
                    if index < 0 do
                        fail InvalidFormatError{"AAC noise scalefactor code is invalid"}
                    noiseEnergy += index - 60
                }

                .scaleFactors[channel, band] = noiseEnergy
            }
            else
            {
                let index = g_ScaleTree.decode(reader)
                if index < 0 do
                    fail InvalidFormatError{"AAC scalefactor code is invalid"}
                scale += index - 60
                .scaleFactors[channel, band] = scale
            }
        }
    }

    mtd decodeTns(reader: *BitReader, channel: s32) fail
    {
        Memory.set(&.tnsFilterCount[channel, 0], 0, #sizeof(.tnsFilterCount[0]))
        let value       = &.ics[channel]
        let windowCount = value.windowSequence == 2 ? 8 : 1
        for window in windowCount
        {
            let filterCount = cast(s32, reader.get(value.windowSequence == 2 ? 1 : 2))
            let coefficientResolution = filterCount ? cast(s32, reader.get1()) : 0
            for filterIndex in filterCount
            {
                let length = cast(s32, reader.get(value.windowSequence == 2 ? 4 : 6))
                var order  = cast(s32, reader.get(value.windowSequence == 2 ? 3 : 5))
                order = Math.min(order, value.windowSequence == 2 ? 7 : 12)
                var direction = 0's32
                var lpc: [13] f64
                lpc[0] = 1
                if order
                {
                    direction = cast(s32, reader.get1())
                    let compress   = cast(s32, reader.get1())
                    let resolution = coefficientResolution + 3
                    let bitCount   = resolution - compress
                    let half       = cast(f64, (1 << (resolution - 1)))
                    let positive   = (half - 0.5) / Math.ConstF64.PiBy2
                    let negative   = (half + 0.5) / Math.ConstF64.PiBy2
                    var reflection: [13] f64
                    for index in order
                    {
                        var raw  = cast(s32, reader.get(bitCount))
                        let sign = 1 << (bitCount - 1)
                        if raw & sign do
                            raw -= sign << 1
                        reflection[index] = Math.sin(cast(f64, raw) / (raw >= 0 ? positive : negative))
                    }

                    for step in 1 until order + 1
                    {
                        let coefficient = reflection[step - 1]
                        let saved       = lpc
                        for index in 1 until step do
                            lpc[index] = saved[index] + coefficient * saved[step - index]
                        lpc[step] = coefficient
                    }
                }

                if filterIndex < 3
                {
                    let filter = &.tns[channel, window, filterIndex]
                    filter.length    = length
                    filter.order     = order
                    filter.direction = direction
                    filter.lpc       = lpc
                    .tnsFilterCount[channel, window] = filterIndex + 1
                }
            }
        }
    }

    mtd(Dimension: s32, Escape: bool) decodeSpectralBand(reader: *BitReader, book: s32, dest: [*] f64, count: s32, gain: f64) fail
    {
        let prefixes = cast(const [*] u32, &g_SpectralPrefixes[book, 0])
        var index    = 0's32
        while index < count
        {
            var packed = 0'u32
            if reader.left() >= 32 do
                packed = prefixes[reader.peekSpectralPrefix()]

            if packed
            {
                reader.bitPos += cast(s32, packed >> SpectralCountShift)
                for component in Dimension
                {
                    let value       = (packed >> (component * SpectralValueBits)) & SpectralValueMask
                    var samplePower = g_SignedPowers[value]
                    #static if Escape
                    {
                        if value == 0 or value == 2 * SpectralValueBias
                        {
                            let magnitude = try reader.readEscapeMagnitude()
                            samplePower = requantize(value == 0 ? -magnitude : magnitude, 1.0)
                        }
                    }

                    dest[index + component] = samplePower * gain
                }
            }
            else
            {
                let symbol = g_SpectralTrees[book].decode(reader)
                if symbol < 0 or reader.overrun do
                    fail InvalidFormatError{"AAC spectral Huffman code is invalid"}
                var values = g_SpectralValues[book, symbol]
                if not BookSigned[book]
                {
                    for component in Dimension where values[component] != 0 do
                        if reader.get1() do
                            values[component] = -values[component]
                }

                #static if Escape
                {
                    for component in Dimension where Math.abs(values[component]) == SpectralValueBias
                    {
                        let magnitude = try reader.readEscapeMagnitude()
                        values[component] = values[component] < 0 ? -magnitude : magnitude
                    }
                }

                for component in Dimension do
                    dest[index + component] = requantize(values[component], gain)
            }

            index += Dimension
        }
    }

    mtd decodeSpectral(reader: *BitReader, channel, bandCount: s32) fail
    {
        Memory.set(&.coefficients[channel, 0], 0, #sizeof(.coefficients[0]))
        let value   = &.ics[channel]
        let offsets = value.windowSequence == 2 ? swbShort(.sampleRateIndex) : swbLong(.sampleRateIndex)
        var line    = 0's32
        for band in bandCount
        {
            let book = .books[channel, band]
            var width: s32
            if value.windowSequence == 2
            {
                let group     = band / value.maxSfb
                let scaleBand = band % value.maxSfb
                width = cast(s32, (offsets[scaleBand + 1] - offsets[scaleBand])) * value.groupLength[group]
            }
            else
            {
                width = cast(s32, (offsets[band + 1] - offsets[band]))
            }

            if not book or book >= 12
            {
                if book == 13 do
                    .noiseSamples += cast(u32, width)
                line += width
                continue
            }

            let gain = bandGain(.scaleFactors[channel, band] - 100)
            let dest = cast([*] f64, &.coefficients[channel, line])

            // AAC's band boundaries are multiples of four for both window sizes.
            if book <= 4 do
                try .decodeSpectralBand'(4, false)(reader, book - 1, dest, width, gain)
            elif book == 11 do
                try .decodeSpectralBand'(2, true)(reader, book - 1, dest, width, gain)
            else do
                try .decodeSpectralBand'(2, false)(reader, book - 1, dest, width, gain)
            line += width
        }
    }

    mtd decodeChannel(reader: *BitReader, channel: s32, commonWindow: bool) fail
    {
        let globalGain = cast(s32, reader.get(8))
        let value      = &.ics[channel]
        if not commonWindow do
            try .parseIcsInfo(reader, value)
        let bandCount = value.windowSequence == 2 ? value.numWindowGroups * value.maxSfb : value.maxSfb
        if bandCount > MaxBands do
            fail InvalidFormatError{"AAC scalefactor-band count is too large"}

        let sectionBits   = value.windowSequence == 2 ? 3 : 5
        let sectionEscape = value.windowSequence == 2 ? 7 : 31
        var flatBand      = 0's32
        for value.numWindowGroups
        {
            var filled = 0's32
            while filled < value.maxSfb
            {
                let book = cast(s32, reader.get(4))
                if book == 12 do
                    fail InvalidFormatError{"AAC section uses the reserved codebook"}
                var length = 0's32
                var increment: s32
                while true
                {
                    increment = cast(s32, reader.get(sectionBits))
                    length    += increment
                    if reader.overrun do
                        fail InvalidFormatError{"AAC section data is truncated"}
                    if increment != sectionEscape do
                        break
                }

                if not length or filled + length > value.maxSfb do
                    fail InvalidFormatError{"AAC section exceeds its window group"}
                for index in length do
                    .books[channel, flatBand + index] = book
                flatBand += length
                filled   += length
            }
        }

        try .decodeScaleFactors(reader, channel, bandCount, globalGain)
        if reader.get1() do
            fail UnsupportedFormatError{"AAC pulse data is not supported"}
        if reader.get1() do
            try .decodeTns(reader, channel)
        else do
            Memory.set(&.tnsFilterCount[channel, 0], 0, #sizeof(.tnsFilterCount[0]))
        if reader.get1() do
            fail UnsupportedFormatError{"AAC gain control is not supported by the Low Complexity profile"}
        try .decodeSpectral(reader, channel, bandCount)
    }

    mtd applyStereoPair(left: s32)
    {
        let right     = left + 1
        let value     = &.ics[left]
        let offsets   = value.windowSequence == 2 ? swbShort(.sampleRateIndex) : swbLong(.sampleRateIndex)
        let bandCount = value.windowSequence == 2 ? value.numWindowGroups * value.maxSfb : value.maxSfb
        var line: s32
        for band in bandCount
        {
            var width: s32
            if value.windowSequence == 2
            {
                let group     = band / value.maxSfb
                let scaleBand = band % value.maxSfb
                width = cast(s32, (offsets[scaleBand + 1] - offsets[scaleBand])) * value.groupLength[group]
            }
            else
            {
                width = cast(s32, (offsets[band + 1] - offsets[band]))
            }

            let rightBook = .books[right, band]
            let intensity = rightBook == 14 or rightBook == 15
            if .usesMs[left] and .msUsed[left, band] and not intensity
            {
                for index in line until line + width
                {
                    let middle = .coefficients[left, index]
                    let side   = .coefficients[right, index]
                    .coefficients[left, index]  = middle + side
                    .coefficients[right, index] = middle - side
                }
            }

            if intensity
            {
                var sign = rightBook == 15 ? 1'f64 : -1'f64
                if .usesMs[left] and .msUsed[left, band] do
                    sign = -sign
                let scale = sign * bandGain(.scaleFactors[right, band])
                for index in line until line + width do
                    .coefficients[right, index] = scale * .coefficients[left, index]
            }

            line += width
        }
    }

    mtd sourceChannel(destinationChannel: s32)->s32
    {
        if .channels <= 2 do
            return destinationChannel
        switch destinationChannel
        {
        case 0:
            return 1

        case 1:
            return 2

        case 2:
            return 0

        case 3:
            if .channels == 6 do
                return 5
            return 3

        case 4:
            if .channels == 6 do
                return 3
            return 4

        case 5:
            return 4

        default:
            return destinationChannel
        }
    }

    mtd synthesizeChannel(channel: s32, output: [*] f32)
    {
        .deinterleaveShort(channel)
        .applyTns(channel)
        .imdctChannel(channel, output)
    }

    mtd prepareSpectrum()
    {
        // Advance the noise generator only after the complete access unit has been validated.
        for channel in .channels do
            .synthesizeNoise(channel)
        for channel in .channels where .pairStart[channel] do
            .applyStereoPair(channel)
    }

    mtd reconstruct(destination: [*] s16)
    {
        .prepareSpectrum()
        if .channels == 2
        {
            var left, right: [FrameSamples] f32
            .synthesizeChannel(0, &left)
            .synthesizeChannel(1, &right)
            let leftPcm  = cast(const [*] f32, &left[0])
            let rightPcm = cast(const [*] f32, &right[0])
            for group in FrameSamples / 4
            {
                let index = 4 * group
                let l     = Simd.load(leftPcm + index)
                let r     = Simd.load(rightPcm + index)
                Simd.store(destination + 2 * index, packStereoPcm16(l, r))
            }

            return
        }

        for channel in .channels
        {
            var pcm: [FrameSamples] f32
            .synthesizeChannel(.sourceChannel(channel), &pcm)
            let output = destination + channel
            for frame in FrameSamples do
                output[frame * .channels] = roundPcm16(pcm[frame])
        }
    }

    mtd parseRaw(packet: const [..] u8) fail
    {
        var reader = BitReader.create(packet.buffer, packet.count)
        .noiseSamples = 0
        var decodedChannels = 0's32
        Memory.set(&.pairStart, 0, #sizeof(.pairStart))
        Memory.set(&.usesMs, 0, #sizeof(.usesMs))
        Memory.set(&.msUsed, 0, #sizeof(.msUsed))

        for
        {
            if reader.overrun or reader.left() < 3 do
                fail InvalidFormatError{"AAC access unit has no end element"}
            let element = cast(s32, reader.get(3))
            if element == 7 do
                break

            if element == 0 or element == 1 or element == 3
            {
                let isPair       = element == 1
                let elementCount = isPair ? 2 : 1
                if decodedChannels + elementCount > .channels or decodedChannels + elementCount > MaxChannels do
                    fail UnsupportedFormatError{"AAC access unit carries more channels than its configuration"}
                let pair = decodedChannels
                discard reader.get(4)
                let commonWindow = isPair and reader.get1() != 0
                if commonWindow
                {
                    var shared: Ics
                    try .parseIcsInfo(&reader, &shared)
                    let msMaskPresent = cast(s32, reader.get(2))
                    if msMaskPresent == 3 do
                        fail InvalidFormatError{"AAC M/S mask mode is reserved"}
                    .ics[pair]     = shared
                    .ics[pair + 1] = shared
                    let bandCount = shared.windowSequence == 2 ? shared.numWindowGroups * shared.maxSfb : shared.maxSfb
                    if msMaskPresent == 1
                    {
                        for band in bandCount do
                            .msUsed[pair, band] = cast(u8, reader.get1())
                    }
                    elif msMaskPresent == 2
                    {
                        for band in bandCount do
                            .msUsed[pair, band] = 1
                    }

                    .usesMs[pair] = msMaskPresent != 0
                }

                for channelOffset in elementCount
                {
                    let channel = decodedChannels + channelOffset
                    try .decodeChannel(&reader, channel, commonWindow)
                }

                if isPair do
                    .pairStart[pair] = true
                decodedChannels += elementCount
            }
            elif element == 6
            {
                var count = cast(s32, reader.get(4))
                if count == 15 do
                    count += cast(s32, reader.get(8)) - 1
                for count do
                    discard reader.get(8)
            }
            else
            {
                fail UnsupportedFormatError{"AAC element is not supported by the Low Complexity decoder"}
            }
        }

        if reader.overrun do
            fail InvalidFormatError{"AAC access unit is truncated"}
        if decodedChannels != .channels do
            fail InvalidFormatError{"AAC access unit channel layout differs from its configuration"}
    }

    mtd decodeRaw(packet: const [..] u8, destination: [*] s16) fail
    {
        try .parseRaw(packet)
        .reconstruct(destination)
    }
}

#[Swag.Inline]
private func packStereoPcm16(left, right: Simd.F32x4)->Simd.S16x8
{
    let half = Simd.splat(0.5'f32)
    let li   = cast #bit (Simd.U32x4, Simd.truncateToS32(left + Math.copysign(half, left)))
    let ri   = cast #bit (Simd.U32x4, Simd.truncateToS32(right + Math.copysign(half, right)))
    let low  = cast #bit (Simd.S32x4, Simd.interleaveLow(li, ri))
    let high = cast #bit (Simd.S32x4, Simd.interleaveHigh(li, ri))
    return Simd.packSigned(low, high)
}

#[Swag.Inline]
private func roundPcm16(sample: f32)->s16
{
    let rounded = Math.trunc(sample + Math.copysign(0.5, sample))
    return cast(s16, Math.clamp(cast(s32, rounded), -32768, 32767))
}

#[Swag.Inline]
private func nextNoiseState(state: u32)->u32
{
    var value = state
    value ^= value << 13
    value ^= value >> 17
    value ^= value << 5
    return value
}

// Applying a power of the linear xorshift transition jumps the same number of
// samples as repeatedly generating noise. One access unit uses at most 6144.
private const NoiseJumpBits = 13
private alias NoiseJumpTable = [NoiseJumpBits, 32] u32
#assert(1 << NoiseJumpBits > MaxChannels * FrameSamples)

private func applyNoiseJump(state: u32, transition: const [*] u32)->u32
{
    var bits = state
    var result: u32
    while bits
    {
        result ^= transition[Swag.trailingZeros(bits)]
        bits   &= bits - 1
    }

    return result
}

private func buildNoiseJumps()->NoiseJumpTable
{
    var jumps: NoiseJumpTable
    for bit in 32 do
        jumps[0, bit] = nextNoiseState(1'u32 << bit)
    for power in 1 until NoiseJumpBits
    {
        let previous = cast(const [*] u32, &jumps[power - 1, 0])
        for bit in 32 do
            jumps[power, bit] = applyNoiseJump(previous[bit], previous)
    }

    return jumps
}

private var g_NoiseJumps: NoiseJumpTable = #run buildNoiseJumps()

private func advanceNoise(state, count: u32)->u32
{
    var result = state
    var skip   = count
    while skip
    {
        let power  = Swag.trailingZeros(skip)
        let jumped = cast(const [*] u32, &g_NoiseJumps[power, 0])
        result = applyNoiseJump(result, jumped)
        skip   &= skip - 1
    }

    return result
}

private func parseChunk(states: [*] AacCodec, packets: const [..] const [..] u8, first, end: u64) fail
{
    for index in first until end do
        try states[index].parseRaw(packets[index])
}

private func synthesizeChunk(states: [*] AacCodec, heads: [*] f32, initialShape: const *[MaxChannels] s32, first, end, stride: u64)
{
    for index in first until end
    {
        let worker = states + index
        for channel in worker.channels
        {
            worker.previousShape[channel] = index ? states[index - 1].ics[channel].windowShape : initialShape[][channel]
            Memory.clear(&worker.overlap[channel, 0], FrameSamples * #sizeof(f32))
        }

        worker.prepareSpectrum()
        let head = heads + index * stride
        for channel in worker.channels do
            worker.synthesizeChannel(channel, head + channel * FrameSamples)
    }
}

private func mergeChunk(states: [*] AacCodec, heads: const [*] f32, initialOverlap: const *[MaxChannels, FrameSamples] f32, count, stride: u64, output: [*] s16)
{
    for index in count
    {
        let worker       = states + index
        let prev         = index ? &states[index - 1].overlap : initialOverlap
        let head         = heads + index * stride
        let packetOutput = output + stride * index
        if worker.channels == 2
        {
            let left      = head
            let right     = head + FrameSamples
            let leftTail  = cast(const [*] f32, &prev[][0, 0])
            let rightTail = cast(const [*] f32, &prev[][1, 0])
            for group in FrameSamples / 4
            {
                let frame = 4 * group
                let l     = Simd.load(left + frame) + Simd.load(leftTail + frame)
                let r     = Simd.load(right + frame) + Simd.load(rightTail + frame)
                Simd.store(packetOutput + 2 * frame, packStereoPcm16(l, r))
            }
        }
        else
        {
            for channel in worker.channels
            {
                let source  = worker.sourceChannel(channel)
                let current = head + source * FrameSamples
                let tail    = cast(const [*] f32, &prev[][source, 0])
                for frame in FrameSamples do
                    packetOutput[frame * worker.channels + channel] = roundPcm16(current[frame] + tail[frame])
            }
        }
    }
}

internal func canDecodePacketBatch(decoder: IPacketCodec)->bool => decoder is AacCodec

// Synthesizes bounded batches in packet order and publishes the decoder's history
// only when every packet succeeds. Discard partial PCM before replaying a failed batch.
internal func decodePacketBatch(decoder: IPacketCodec, packets: const [..] const [..] u8, output: [..] s16, laneCount: u64) fail
{
    let initial = try cast(*AacCodec, decoder)
    let stride  = cast(u64, initial.channels) * FrameSamples
    if packets.count > MaxPacketBatchSize or
       output.count != packets.count * stride or
       not laneCount or
       laneCount > MaxPacketBatchLanes do
        fail BadParameterError{"AAC packet batch dimensions are invalid"}
    if not packets.count do
        return

    let capacity = Math.min(packets.count, BatchStateCount)
    var scratch: Array'AacCodec
    scratch.resize(capacity)
    let states = scratch.storage()
    var samples: Array'f32
    samples.reserve(capacity * stride)
    let heads = samples.storage()
    for index in capacity
    {
        states[index].sampleRateIndex = initial.sampleRateIndex
        states[index].channels        = initial.channels
    }

    var seed          = initial.pnsState
    var overlap       = initial.overlap
    var previousShape = initial.previousShape
    var position: u64
    while position < packets.count
    {
        let count  = Math.min(capacity, packets.count - position)
        let input  = packets[position until position + count]
        let target = output.buffer + stride * position
        let lanes  = Math.min(laneCount, count)
        var group: Swag.TaskGroup

        // Entropy parsing has no overlap or noise-generator dependency.
        for lane in 1 until lanes
        {
            let first = count * lane / lanes
            let end   = count * (lane + 1) / lanes
            group.spawn(func|states, input, first, end|() fail { try parseChunk(states, input, first, end) })
        }

        try parseChunk(states, input, 0, count / lanes)
        try group.join()

        // Seed each unit from the noise samples consumed by all preceding units.
        for index in count
        {
            states[index].pnsState = seed
            seed = advanceNoise(seed, states[index].noiseSamples)
        }

        // Adjacent window shapes are now known. Workers write head and tail contributions.
        let shape = &previousShape
        for lane in 1 until lanes
        {
            let first = count * lane / lanes
            let end   = count * (lane + 1) / lanes
            group.spawn(func|states, heads, shape, first, end, stride|() { synthesizeChunk(states, heads, shape, first, end, stride) })
        }

        synthesizeChunk(states, heads, shape, 0, count / lanes, stride)
        try group.join()
        mergeChunk(states, heads, &overlap, count, stride, target)
        let final = states + count - 1
        overlap = final.overlap
        for channel in initial.channels do
            previousShape[channel] = final.ics[channel].windowShape
        position += count
    }

    initial.pnsState      = seed
    initial.previousShape = previousShape
    initial.overlap       = overlap
}

impl IPacketCodec for AacCodec
{
    mtd impl canDecode(encoding: SoundFileEncoding)->bool => encoding == .AacLc

    mtd impl initialize(config: const [..] u8, sampleRateHz, channels: u32) fail
    {
        if config.count < 2 do
            fail InvalidFormatError{"AAC AudioSpecificConfig is truncated"}
        var reader     = BitReader.create(config.buffer, config.count)
        let objectType = reader.get(5)
        if objectType != 2 do
            fail UnsupportedFormatError{"audio decoder supports AAC Low Complexity only"}
        let rateIndex = reader.get(4)
        if rateIndex >= 12 do
            fail UnsupportedFormatError{"AAC explicit and reserved sample rates are not supported"}
        let channelConfig = reader.get(4)
        if channelConfig < 1 or channelConfig > MaxChannels do
            fail UnsupportedFormatError{"audio decoder supports AAC channel configurations 1 through 6"}
        if SampleRates[rateIndex] != sampleRateHz or channelConfig != channels do
            fail InvalidFormatError{"AAC configuration does not match its container track"}
        if reader.get1() do
            fail UnsupportedFormatError{"AAC 960-sample frames are not supported"}
        if reader.get1()
        {
            discard reader.get(14)
            fail UnsupportedFormatError{"AAC core-coder dependency is not supported"}
        }

        if reader.get1() do
            fail UnsupportedFormatError{"AAC extension flags are not supported"}
        if reader.overrun do
            fail InvalidFormatError{"AAC AudioSpecificConfig is truncated"}

        .sampleRateIndex = cast(s32, rateIndex)
        .channels        = cast(s32, channels)
        .resetState()
    }

    mtd impl reset()
    {
        .resetState()
    }

    mtd impl decodePacket(destination: [*] void, destinationSize: u64, packet: const [..] u8)->u64 fail
    {
        let required = cast(u64, FrameSamples) * cast(u64, .channels) * #sizeof(s16)
        if destinationSize < required do
            fail BadParameterError{"AAC destination buffer is too small"}
        try .decodeRaw(packet, cast([*] s16, destination))
        return required
    }
}

#init
{
    initializeTables()
    registerPacketCodec'AacCodec()
}
