#global namespace Aac

using Core, Core.Errors, Core.Math

private const FrameSamples = 1024
private const MaxBands = 8 * 52
private const MaxChannels = 6

private struct BitReader
{
    data:    const [*] u8
    length:  s32
    bitPos:  s32
    overrun: bool
}

private impl BitReader
{
    func create(data: const [*] u8, length: u64)->BitReader => {data, cast(s32) length, 0, false}

    mtd left()->s32 => .length * 8 - .bitPos

    mtd get(count: s32)->u32
    {
        var value: u32
        for count
        {
            let byteIndex = .bitPos >> 3
            let bitIndex  = 7 - (.bitPos & 7)
            if byteIndex >= .length do
                .overrun = true
            value   = (value << 1) | (byteIndex < .length ? (cast(u32) .data[byteIndex] >> cast(u32) bitIndex) & 1 : 0)
            .bitPos += 1
        }

        return value
    }

    mtd get1()->u32 => .get(1)
}

private struct HuffTree
{
    child: [600, 2] s32
    nodes: s32 = 1
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
            let branch = cast(s32) ((code >> cast(u32) bit) & 1)
            if !bit
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
                .nodes             += 1
            }

            at  = .child[at, branch]
            bit -= 1
        }
    }

    mtd const decode(reader: *BitReader)->s32
    {
        var at = 0's32
        for 24
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
    size:     s32
    quarter:  s32
    log2Size: s32
    reverse:  [512] s32
    fftReal:  [512] f64
    fftImag:  [512] f64
    twReal:   [512] f64
    twImag:   [512] f64
}

private impl ImdctPlan
{
    mtd init(size: s32)
    {
        .size     = size
        .quarter  = size / 4
        .log2Size = 0
        while (1 << .log2Size) < .quarter do
            .log2Size += 1

        for i in cast(u64) .quarter
        {
            var value: u32
            for bit in cast(u64) .log2Size do
                value = (value << 1) | ((cast(u32) i >> cast(u32) bit) & 1)
            .reverse[i] = cast(s32) value
        }

        let pi = Math.ConstF64.Pi
        for i in cast(u64) .quarter
        {
            let angle = 2.0 * pi * cast(f64) i / cast(f64) .quarter
            .fftReal[i] = Math.cos(angle)
            .fftImag[i] = Math.sin(angle)
        }

        let half = size / 2
        for i in cast(u64) .quarter
        {
            let angle = pi * (cast(f64) i + 0.125) / cast(f64) half
            .twReal[i] = Math.cos(angle)
            .twImag[i] = -Math.sin(angle)
        }
    }

    mtd const run(spectrum: const [*] f64, output: [*] f64)
    {
        let half    = .size / 2
        let quarter = .quarter
        var real: [512] f64
        var imag: [512] f64
        for k in cast(u64) quarter
        {
            let a = spectrum[2 * k] * 0.5
            let b = -spectrum[cast(u64) half - 1 - 2 * k] * 0.5
            real[k] = a * .twReal[k] + b * .twImag[k]
            imag[k] = -a * .twImag[k] + b * .twReal[k]
        }

        for i in cast(u64) quarter
        {
            let reversed = cast(u64) .reverse[i]
            if reversed > i
            {
                let savedReal = real[i]
                let savedImag = imag[i]
                real[i]        = real[reversed]
                imag[i]        = imag[reversed]
                real[reversed] = savedReal
                imag[reversed] = savedImag
            }
        }

        var length = 2's32
        while length <= quarter
        {
            let butterfly = length >> 1
            let stride    = quarter / length
            var base      = 0's32
            while base < quarter
            {
                for j in cast(u64) butterfly
                {
                    let a  = cast(u64) base + j
                    let b  = a + cast(u64) butterfly
                    let tw = j * cast(u64) stride
                    let xr = real[b] * .fftReal[tw] - imag[b] * .fftImag[tw]
                    let xi = real[b] * .fftImag[tw] + imag[b] * .fftReal[tw]
                    real[b] = real[a] - xr
                    imag[b] = imag[a] - xi
                    real[a] += xr
                    imag[a] += xi
                }

                base += length
            }

            length <<= 1
        }

        var folded: [1024] f64
        let inverse = 2.0 / cast(f64) quarter
        for i in cast(u64) quarter
        {
            let realValue = real[i] * inverse
            let imagValue = imag[i] * inverse
            folded[2 * i] = realValue * .twReal[i] + imagValue * .twImag[i]
            folded[cast(u64) half - 1 - 2 * i] = -realValue * .twImag[i] + imagValue * .twReal[i]
        }

        for i in cast(u64) quarter
        {
            let b = folded[cast(u64) quarter + i] * 0.5
            let a = -folded[i] * 0.5
            output[i] = b
            output[cast(u64) (2 * quarter) - 1 - i] = -b
            output[cast(u64) (3 * quarter) + i]     = a
            output[cast(u64) (3 * quarter) - 1 - i] = a
        }
    }
}

private var g_SpectralTrees: [11] HuffTree
private var g_ScaleTree: HuffTree
private var g_ImdctLong: ImdctPlan
private var g_ImdctShort: ImdctPlan
private var g_LongWindows: [2, 1024] f64
private var g_ShortWindows: [2, 128] f64

private func initializeTables()
{
    for book in 11
    {
        g_SpectralTrees[book].reset()
        let bits  = specBits(cast(u32) book)
        let codes = specCodes(cast(u32) book)
        for index in cast(u64) BookSize[book] where bits[index] != 0 do
            g_SpectralTrees[book].insert(codes[index], bits[index], cast(s32) index)
    }

    g_ScaleTree.reset()
    for index in 121 where ScfBits[index] != 0 do
        g_ScaleTree.insert(ScfCodes[index], ScfBits[index], cast(s32) index)

    g_ImdctLong.init(2048)
    g_ImdctShort.init(256)

    for index in 1024 do
        g_LongWindows[0, index] = Math.sin(Math.ConstF64.Pi / 2048.0 * (cast(f64) index + 0.5))
    for index in 128 do
        g_ShortWindows[0, index] = Math.sin(Math.ConstF64.Pi / 256.0 * (cast(f64) index + 0.5))
    initializeKbdWindow(&g_LongWindows[1, 0], 4.0, 1024)
    initializeKbdWindow(&g_ShortWindows[1, 0], 6.0, 128)
}

private func initializeKbdWindow(window: [*] f64, alpha: f64, half: s32)
{
    var cumulative: [1024] f64
    let scaled = alpha * Math.ConstF64.Pi / cast(f64) half
    let factor = scaled * scaled
    var sum    = 0'f64
    for index in cast(u64) half
    {
        let value = cast(f64) index * cast(f64) (half - cast(s32) index) * factor
        var b     = 1'f64
        var step  = 50's32
        while step > 0
        {
            b    = b * value / cast(f64) (step * step) + 1.0
            step -= 1
        }

        sum               += b
        cumulative[index] = sum
    }

    sum += 1.0
    for index in cast(u64) half do
        window[index] = Math.sqrt(cumulative[index] / sum)
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
    overlap:         [MaxChannels, FrameSamples] f64
    previousShape:   [MaxChannels] s32
    pnsState:        u32
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
        value.windowSequence = cast(s32) reader.get(2)
        value.windowShape    = cast(s32) reader.get1()
        if value.windowSequence == 2
        {
            value.maxSfb = cast(s32) reader.get(4)
            let grouping = reader.get(7)
            value.numWindows      = 8
            value.numWindowGroups = 1
            value.groupLength[0]  = 1
            for window in 1 until 8
            {
                let shares = (grouping >> cast(u32) (7 - window)) & 1
                if shares do
                    value.groupLength[value.numWindowGroups - 1] += 1
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
            value.maxSfb          = cast(s32) reader.get(6)
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
        .pnsState ^= .pnsState << 13
        .pnsState ^= .pnsState >> 17
        .pnsState ^= .pnsState << 5
        return cast(f64) (.pnsState >> 8) * (2.0 / 16777216.0) - 1.0
    }

    mtd dequantizeBand(channel, book, scale, first, last: s32)
    {
        if book == 0 or book == 14 or book == 15
        {
            for index in first until last do
                .coefficients[channel, index] = 0
            return
        }

        if book == 13
        {
            var energy = 0'f64
            for index in first until last
            {
                let noise = .randomNoise()
                .coefficients[channel, index] = noise
                energy += noise * noise
            }

            let width  = last - first
            let target = Math.pow(2.0, 0.25 * cast(f64) (scale - 100))
            let norm   = energy > 0 ? target * Math.sqrt(cast(f64) width / energy) : 0.0
            for index in first until last do
                .coefficients[channel, index] *= norm
            return
        }

        let gain = Math.pow(2.0, 0.25 * cast(f64) (scale - 100))
        for index in first until last
        {
            let value     = .coefficients[channel, index]
            let magnitude = Math.abs(value)
            .coefficients[channel, index] = (value < 0 ? -1.0 : 1.0) * Math.pow(magnitude, 4.0 / 3.0) * gain
        }
    }

    mtd inverseQuantize(channel: s32)
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
                    let width = cast(s32) (offsets[band + 1] - offsets[band]) * value.groupLength[group]
                    .dequantizeBand(channel, .books[channel, bandIndex], .scaleFactors[channel, bandIndex], line, line + width)
                    line      += width
                    bandIndex += 1
                }
            }
        }
        else
        {
            let offsets = swbLong(.sampleRateIndex)
            for band in value.maxSfb do
                .dequantizeBand(channel, .books[channel, band], .scaleFactors[channel, band], offsets[band], offsets[band + 1])
            for line in offsets[value.maxSfb] until FrameSamples do
                .coefficients[channel, line] = 0
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
        let numBands = isShort ? cast(s32) NumSwbShort[.sampleRateIndex] : cast(s32) NumSwbLong[.sampleRateIndex]
        var maximum  = isShort ? cast(s32) TnsMaxBandsShort[.sampleRateIndex] : cast(s32) TnsMaxBandsLong[.sampleRateIndex]
        maximum = Math.min(maximum, Math.min(value.maxSfb, numBands))
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
                if !filter.order do
                    continue
                let start = cast(s32) offsets[Math.min(bottom, maximum)]
                let end   = cast(s32) offsets[Math.min(top, maximum)]
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
                        order          -= 1
                    }

                    history[0] = valueAtLine
                    .coefficients[channel, base + line] = valueAtLine
                    line       += increment
                }
            }
        }
    }

    mtd imdctChannel(channel: s32, output: [*] f64)
    {
        let value         = &.ics[channel]
        var time: [2048] f64
        let currentShape  = value.windowShape
        let previousShape = .previousShape[channel]

        if value.windowSequence != 2
        {
            var transformed: [2048] f64
            g_ImdctLong.run(&.coefficients[channel, 0], &transformed)
            for index in 2048
            {
                var window = 0'f64
                if index < 1024
                {
                    if value.windowSequence == 3
                    {
                        if index < 448 do
                            window = 0
                        elif index < 576 do
                            window = g_ShortWindows[previousShape, index - 448]
                        else do
                            window = 1
                    }
                    else do
                        window = g_LongWindows[previousShape, index]
                }
                else
                {
                    if value.windowSequence == 1
                    {
                        let offset = index - 1024
                        if offset < 448 do
                            window = 1
                        elif offset < 576 do
                            window = g_ShortWindows[currentShape, 575 - offset]
                        else do
                            window = 0
                    }
                    else do
                        window = g_LongWindows[currentShape, 2047 - index]
                }

                time[index] = transformed[index] * window
            }
        }
        else
        {
            for window in 8
            {
                var transformed: [256] f64
                g_ImdctShort.run(&.coefficients[channel, 128 * window], &transformed)
                let leftShape = window == 0 ? previousShape : currentShape
                let base      = 448 + 128 * window
                for index in 256
                {
                    let windowValue = index < 128 ? g_ShortWindows[leftShape, index] : g_ShortWindows[currentShape, 255 - index]
                    time[base + index] += transformed[index] * windowValue
                }
            }
        }

        for index in FrameSamples
        {
            output[index]            = (time[index] + .overlap[channel, index]) / 32768.0
            .overlap[channel, index] = time[FrameSamples + index]
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
            if !book
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
                    noiseEnergy += cast(s32) reader.get(9) - 256
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
            let filterCount           = cast(s32) reader.get(value.windowSequence == 2 ? 1 : 2)
            let coefficientResolution = filterCount ? cast(s32) reader.get1() : 0
            for filterIndex in filterCount
            {
                let length = cast(s32) reader.get(value.windowSequence == 2 ? 4 : 6)
                var order  = cast(s32) reader.get(value.windowSequence == 2 ? 3 : 5)
                order = Math.min(order, value.windowSequence == 2 ? 7 : 12)
                var direction = 0's32
                var lpc: [13] f64
                lpc[0] = 1
                if order
                {
                    direction = cast(s32) reader.get1()
                    let compress   = cast(s32) reader.get1()
                    let resolution = coefficientResolution + 3
                    let bitCount   = resolution - compress
                    let half       = cast(f64) (1 << (resolution - 1))
                    let positive   = (half - 0.5) / Math.ConstF64.PiBy2
                    let negative   = (half + 0.5) / Math.ConstF64.PiBy2
                    var reflection: [13] f64
                    for index in order
                    {
                        var raw  = cast(s32) reader.get(bitCount)
                        let sign = 1 << (bitCount - 1)
                        if raw & sign do
                            raw -= sign << 1
                        reflection[index] = Math.sin(cast(f64) raw / (raw >= 0 ? positive : negative))
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
                    filter.length                    = length
                    filter.order                     = order
                    filter.direction                 = direction
                    filter.lpc                       = lpc
                    .tnsFilterCount[channel, window] = filterIndex + 1
                }
            }
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
                width = cast(s32) (offsets[scaleBand + 1] - offsets[scaleBand]) * value.groupLength[group]
            }
            else do
                width = cast(s32) (offsets[band + 1] - offsets[band])

            if !book or book >= 12
            {
                line += width
                continue
            }

            let dimension = cast(s32) BookDim[book - 1]
            let largest   = cast(s32) BookLav[book - 1]
            let signed    = BookSigned[book - 1] != 0
            let end       = line + width
            var index     = line
            while index < end
            {
                let symbol = g_SpectralTrees[book - 1].decode(reader)
                if symbol < 0 or reader.overrun do
                    fail InvalidFormatError{"AAC spectral Huffman code is invalid"}
                var values: [4] s32
                var packed    = symbol
                var component = dimension - 1
                if signed
                {
                    while component >= 0
                    {
                        values[component] = packed % (2 * largest + 1) - largest
                        packed            /= 2 * largest + 1
                        component         -= 1
                    }
                }
                else
                {
                    let radix = book == 11 ? 17 : largest + 1
                    while component >= 0
                    {
                        values[component] = packed % radix
                        packed            /= radix
                        component         -= 1
                    }

                    for item in dimension where values[item] != 0 do
                        if reader.get1() do
                            values[item] = -values[item]
                    if book == 11
                    {
                        for item in dimension where Math.abs(values[item]) == 16
                        {
                            var leading = 0's32
                            while reader.get1() do
                                leading += 1
                            if leading > 11 do
                                fail InvalidFormatError{"AAC escape coefficient is too large"}
                            let magnitude = (1 << (leading + 4)) + cast(s32) reader.get(leading + 4)
                            values[item] = values[item] < 0 ? -magnitude : magnitude
                        }
                    }
                }

                for item in dimension where index + item < end do
                    .coefficients[channel, index + item] = values[item]
                index += dimension
            }

            line = end
        }
    }

    mtd decodeChannel(reader: *BitReader, channel: s32, commonWindow: bool) fail
    {
        let globalGain = cast(s32) reader.get(8)
        let value      = &.ics[channel]
        if !commonWindow do
            .parseIcsInfo(reader, value)
        let bandCount = value.windowSequence == 2 ? value.numWindowGroups * value.maxSfb : value.maxSfb
        if bandCount > MaxBands do
            fail InvalidFormatError{"AAC scalefactor-band count is too large"}

        let sectionBits   = value.windowSequence == 2 ? 3 : 5
        let sectionEscape = value.windowSequence == 2 ? 7 : 31
        var flatBand      = 0's32
        for group in value.numWindowGroups
        {
            discard group
            var filled = 0's32
            while filled < value.maxSfb
            {
                let book = cast(s32) reader.get(4)
                if book == 12 do
                    fail InvalidFormatError{"AAC section uses the reserved codebook"}
                var length = 0's32
                var increment: s32
                while true
                {
                    increment = cast(s32) reader.get(sectionBits)
                    length    += increment
                    if reader.overrun do
                        fail InvalidFormatError{"AAC section data is truncated"}
                    if increment != sectionEscape do
                        break
                }

                if !length or filled + length > value.maxSfb do
                    fail InvalidFormatError{"AAC section exceeds its window group"}
                for index in length do
                    .books[channel, flatBand + index] = book
                flatBand += length
                filled   += length
            }
        }

        .decodeScaleFactors(reader, channel, bandCount, globalGain)
        if reader.get1() do
            fail UnsupportedFormatError{"AAC pulse data is not supported"}
        if reader.get1() do
            .decodeTns(reader, channel)
        else do
            Memory.set(&.tnsFilterCount[channel, 0], 0, #sizeof(.tnsFilterCount[0]))
        if reader.get1() do
            fail UnsupportedFormatError{"AAC gain control is not supported by the Low Complexity profile"}
        .decodeSpectral(reader, channel, bandCount)
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
                width = cast(s32) (offsets[scaleBand + 1] - offsets[scaleBand]) * value.groupLength[group]
            }
            else do
                width = cast(s32) (offsets[band + 1] - offsets[band])

            let rightBook = .books[right, band]
            let intensity = rightBook == 14 or rightBook == 15
            if .usesMs[left] and .msUsed[left, band] and !intensity
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
                let scale = sign * Math.pow(2.0, 0.25 * cast(f64) .scaleFactors[right, band])
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

    mtd reconstruct(destination: [*] s16)
    {
        for channel in .channels do
            .inverseQuantize(channel)
        for channel in .channels where .pairStart[channel] do
            .applyStereoPair(channel)

        var channelPcm: [MaxChannels, FrameSamples] f64
        for channel in .channels
        {
            .deinterleaveShort(channel)
            .applyTns(channel)
            .imdctChannel(channel, &channelPcm[channel, 0])
        }

        for frame in FrameSamples
        {
            for channel in .channels
            {
                let source = .sourceChannel(channel)
                let scaled = Math.clamp(cast(s32) Math.round(channelPcm[source, frame] * 32768.0), -32768, 32767)
                destination[frame * .channels + channel] = cast(s16) scaled
            }
        }
    }

    mtd decodeRaw(packet: const [..] u8, destination: [*] s16) fail
    {
        var reader          = BitReader.create(@dataof(packet), @countof(packet))
        var decodedChannels = 0's32
        Memory.set(&.pairStart, 0, #sizeof(.pairStart))
        Memory.set(&.usesMs, 0, #sizeof(.usesMs))
        Memory.set(&.msUsed, 0, #sizeof(.msUsed))

        for
        {
            if reader.overrun or reader.left() < 3 do
                fail InvalidFormatError{"AAC access unit has no end element"}
            let element = cast(s32) reader.get(3)
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
                    .parseIcsInfo(&reader, &shared)
                    let msMaskPresent = cast(s32) reader.get(2)
                    if msMaskPresent == 3 do
                        fail InvalidFormatError{"AAC M/S mask mode is reserved"}
                    .ics[pair]     = shared
                    .ics[pair + 1] = shared
                    let bandCount = shared.windowSequence == 2 ? shared.numWindowGroups * shared.maxSfb : shared.maxSfb
                    if msMaskPresent == 1
                    {
                        for band in bandCount do
                            .msUsed[pair, band] = cast(u8) reader.get1()
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
                    .decodeChannel(&reader, channel, commonWindow)
                }

                if isPair do
                    .pairStart[pair] = true
                decodedChannels += elementCount
            }
            elif element == 6
            {
                var count = cast(s32) reader.get(4)
                if count == 15 do
                    count += cast(s32) reader.get(8) - 1
                for count do
                    discard reader.get(8)
            }
            else do
                fail UnsupportedFormatError{"AAC element is not supported by the Low Complexity decoder"}
        }

        if reader.overrun do
            fail InvalidFormatError{"AAC access unit is truncated"}
        if decodedChannels != .channels do
            fail InvalidFormatError{"AAC access unit channel layout differs from its configuration"}
        .reconstruct(destination)
    }
}

impl IPacketCodec for AacCodec
{
    mtd impl canDecode(encoding: SoundFileEncoding)->bool => encoding == .AacLc

    mtd impl initialize(config: const [..] u8, sampleRateHz, channels: u32) fail
    {
        if @countof(config) < 2 do
            fail InvalidFormatError{"AAC AudioSpecificConfig is truncated"}
        var reader     = BitReader.create(@dataof(config), @countof(config))
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

        .sampleRateIndex = cast(s32) rateIndex
        .channels        = cast(s32) channels
        .resetState()
    }

    mtd impl reset()
    {
        .resetState()
    }

    mtd impl decodePacket(destination: [*] void, destinationSize: u64, packet: const [..] u8)->u64 fail
    {
        let required = cast(u64) FrameSamples * cast(u64) .channels * #sizeof(s16)
        if destinationSize < required do
            fail BadParameterError{"AAC destination buffer is too small"}
        .decodeRaw(packet, cast([*] s16) destination)
        return required
    }
}

#init
{
    initializeTables()
    registerPacketCodec'AacCodec()
}
