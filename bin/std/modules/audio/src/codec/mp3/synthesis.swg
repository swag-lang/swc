//! Format: MPEG-1, MPEG-2, and MPEG-2.5 Layer III packet decoder component.
//! Supported: Layer III at every sampling frequency and bit rate of the three versions, mono, dual channel, joint stereo with mid/side and intensity coupling, long, short and mixed blocks, and the bit reservoir.
//! Not supported: Layer I and Layer II, free-format streams, and the CRC the frame header may carry.
//! Role: This file owns what turns spectral lines back into samples: reordering, alias reduction, the inverse transform, and the polyphase filter bank.
//
#global namespace Mp3
#global internal

using Core

// Spectral lines of one granule of one channel.
//
// The 576 lines of a granule are 32 subbands of 18, in that order: line `band * 18 + index`.
alias Granule576     = [576] f32
alias SubbandOverlap = [18, 32] f32

private const FilterHistory = 32'u64
private const FilterMask    = FilterHistory - 1
// Four windows can start three rows apart and read fifteen more rows each.
private const FilterMirrorRows = 18'u64
private const FilterRows = FilterHistory + FilterMirrorRows

// What one channel carries from one granule to the next.
//
// The inverse transform of a granule overlaps the one before it, and the filter bank looks back
// over the last sixteen blocks it produced, so a channel cannot be decoded from its own granule
// alone. A seek resets both.
struct ChannelState
{
    overlap:      SubbandOverlap         // Second half of the previous inverse transform, grouped by time slot.
    filter:       [FilterRows, 32] f32 // Even and odd bins for paired samples.
    firstHistory: [FilterHistory * 2] f32 // Two copies let one load cross the history wrap.
    overlapEnd:   u32                    // Exclusive upper bound of the saved overlap.
    filterAt:     u64                    // Newest block of the delay line.
}

impl ChannelState
{
    // Restores the state a decode starts from, which is what a seek needs.
    mtd reset()
    {
        Memory.set(cast(*void, &.overlap[0, 0]), 0, #sizeof(f32) * 32 * 18)
        Memory.set(cast(*void, &.filter[0, 0]), 0, #sizeof(f32) * FilterRows * 32)
        Memory.set(cast(*void, &.firstHistory[0]), 0, #sizeof(f32) * .firstHistory.count)
        .overlapEnd = 0
        .filterAt = 0
    }
}

// Puts the lines of the short-block region back in subband order.
//
// Inside one scalefactor band a short block stores its three windows one after another, which is
// the order the entropy coder wants; the transform wants the three interleaved. `bands` lists the
// width of each window of each band, three entries per band, and `firstBand` is where the short
// region starts — nonzero only for a mixed block, whose first bands stay long.
func reorderShortBlocks(lines: *Granule576, bands: const [..] u8, firstBand, firstLine: u32)
{
    var scratch: Granule576
    var source  = firstLine
    var band    = cast(u64, firstBand)
    var written = 0'u64

    while band < bands.count
    {
        let width = cast(u32, bands[band])
        if not width do
            break
        band += 3

        if source + width * 3 > 576 do
            break
        for index in width
        {
            for window in 3'u32 do
                scratch[written + cast(u64, (index * 3 + window))] = lines[][source + window * width + index]
        }

        written += cast(u64, width) * 3
        source  += width * 3
    }

    for index in written do
        lines[][cast(u64, firstLine) + index] = scratch[index]
}

// Undoes the aliasing the encoder's polyphase analysis left between neighbouring subbands.
//
// The eight samples on each side of a subband boundary are rotated back by the normative
// coefficients. A short block was never aliased this way, so `subbandCount` stops before its
// first subband.
func reduceAlias(lines: *Granule576, subbandCount: u32)
{
    using Math.Simd
    const Reverse = cast(U32x4, [3'u32, 2, 1, 0])
    for subband in 1 until subbandCount
    {
        let boundary = cast(u64, subband) * 18
        for group in 2'u64
        {
            let i     = group * 4
            let below = &lines[][boundary - i - 4]
            let above = &lines[][boundary + i]
            let a     = permute(load(below), Reverse)
            let b     = load(above)
            let cs    = load(&AliasCs[i])
            let ca    = load(&AliasCa[i])
            store(below, permute(a * cs - b * ca, Reverse))
            store(above, b * cs + a * ca)
        }
    }
}

// Reciprocals for a cosine half-angle split. A DCT-II uses angle pi*(i+1/2)/N,
// and a DCT-IV reduces to a DCT-II with half that angle.
private func(N: u64) buildCosineReciprocals(divisor: f64)->[N] f32
{
    var factors: #returntype
    for i in N
    {
        let angle = Math.ConstF64.Pi * (cast(f64, i) + 0.5) / divisor
        factors[i] = cast(f32, (0.5 / Math.cos(angle)))
    }

    return factors
}

private func buildDct9Matrix()->[9, 4] f32
{
    var matrix: #returntype
    for k in 9'u64
    {
        for i in 4'u64
        {
            let angle = Math.ConstF64.Pi * (cast(f64, i) + 0.5) * cast(f64, k) / 9.0
            matrix[k, i] = cast(f32, Math.cos(angle))
        }
    }

    return matrix
}

private const Dct9Matrix = #run buildDct9Matrix()

#[Swag.Inline]
private func(T, K: u64) dct9Bin(pairs: const [*] T, middle: T)->T
{
    var sum: T
    #static if (K & 1) == 0
    {
        #static if (K & 2) == 0 do
            sum = middle
        else do
            sum = -middle
    }

    sum += pairs[0] * Dct9Matrix[K, 0]
    sum += pairs[1] * Dct9Matrix[K, 1]
    sum += pairs[2] * Dct9Matrix[K, 2]
    sum += pairs[3] * Dct9Matrix[K, 3]
    return sum
}

// The outer pairs form independent even and odd cosine sums. Finish the
// even outputs before loading the odd differences to limit live vectors.
#[Swag.Inline]
private func(T) factoredDct9(input: const [*] T, output: [*] T)
{
    scope
    {
        let s0 = input[0] + input[8]
        let s1 = input[1] + input[7]
        let s2 = input[2] + input[6]
        let s3 = input[3] + input[5]
        let middle = input[4]

        const C20  = 0.939692621'f32
        const C100 = -0.173648178'f32
        const C140 = -0.766044443'f32
        let u = s0 - s3
        let v = s2 - s3
        let even0 = u * C20 + v * C100
        let even1 = u * C100 + v * C140
        let balance = s1 * 0.5 - middle
        let sides = s0 + s2 + s3
        output[0] = middle + s1 + sides
        output[2] = even0 + balance
        output[4] = even0 + even1 - balance
        output[6] = sides * 0.5 - s1 - middle
        output[8] = -even1 - balance
    }
    scope
    {
        let d0 = input[0] - input[8]
        let d1 = input[1] - input[7]
        let d2 = input[2] - input[6]
        let d3 = input[3] - input[5]

        const C30 = 0.866025404'f32
        const C50 = 0.642787610'f32
        const C70 = 0.342020143'f32
        let difference = d3 - d2
        let odd0 = (d0 + d3) * C50 + difference * C70
        let odd1 = (d0 + d2) * C70 - difference * C50
        let middle = d1 * C30
        output[1] = odd0 + odd1 + middle
        output[3] = (d0 - d2 - d3) * C30
        output[5] = odd0 - middle
        output[7] = odd1 - middle
    }
}

// Lee's even half supplies even indices. Each odd bin adds its next neighbor.
#[Swag.Inline]
private func(N: u64, T) mergeDctHalves(input: const [*] T, output: [*] T)
{
    const Half = N / 2
    for i in Half - 1
    {
        output[2 * i]     = input[i]
        output[2 * i + 1] = input[Half + i] + input[Half + i + 1]
    }
    output[N - 2] = input[Half - 1]
    output[N - 1] = input[N - 1]
}

#[Swag.Inline]
private func(T, Step: u64, AddOddNeighbors: bool) writeDct4(a, b, c, d: T, output: [*] T)
{
    const Factors = #run buildCosineReciprocals'2(4'f64)
    let evenLo = a + d
    let evenHi = b + c
    let oddLo  = (a - d) * Factors[0]
    let oddHi  = (b - c) * Factors[1]
    let last   = (oddLo - oddHi) * 0.707106781
    let bin0   = evenLo + evenHi
    let bin1   = (oddLo + oddHi) + last
    let bin2   = (evenLo - evenHi) * 0.707106781
    #static if AddOddNeighbors
    {
        output[0]        = bin0 + bin1
        output[Step]     = bin1 + bin2
        output[2 * Step] = bin2 + last
        output[3 * Step] = last
    }
    else
    {
        output[0]        = bin0
        output[Step]     = bin1
        output[2 * Step] = bin2
        output[3 * Step] = last
    }
}

#[Swag.Inline]
private func(T, Step: u64) writeDct8(input: const [*] T, output: [*] T)
{
    const Factors = #run buildCosineReciprocals'4(8'f64)
    let a = input[0]
    let b = input[1]
    let c = input[2]
    let d = input[3]
    let e = input[4]
    let f = input[5]
    let g = input[6]
    let h = input[7]
    writeDct4'(T, 2 * Step, false)(a + h, b + g, c + f, d + e, output)
    writeDct4'(T, 2 * Step, true)((a - h) * Factors[0], (b - g) * Factors[1],
                          (c - f) * Factors[2], (d - e) * Factors[3], output + Step)
}

// Unnormalized DCT-II: X[k] = sum_i x[i] cos(pi*(i+1/2)*k/N).
//
// Pairing opposite input samples separates even and odd outputs. Lee's half-angle factor
// reduces each half to a DCT-II again. The only odd lengths reached are the MP3 IMDCT
// leaves of three and nine points. Each layer exchanges the input and output buffers,
// so recursion needs no separate arrays for its even and odd branches.
#[Swag.Inline]
private func(N: u64, T) dct(input: [*] T, output: [*] T)
{
    #static if N == 2
    {
        output[0] = input[0] + input[1]
        output[1] = (input[0] - input[1]) * 0.707106781
    }
    elif N == 4
    {
        writeDct4'(T, 1, false)(input[0], input[1], input[2], input[3], output)
    }
    elif N == 8
    {
        writeDct8'(T, 1)(input, output)
    }
    elif N == 3
    {
        let ends = input[0] + input[2]
        output[0] = ends + input[1]
        output[1] = (input[0] - input[2]) * 0.866025404
        output[2] = ends * 0.5 - input[1]
    }
    elif N == 9 and T == Math.Simd.F32x4
    {
        factoredDct9'T(input, output)
    }
    elif N == 9
    {
        const Half = N / 2
        var sums, differences: [Half] T
        for i in Half
        {
            let first = input[i]
            let last  = input[N - 1 - i]
            sums[i]        = first + last
            differences[i] = first - last
        }

        output[0] = dct9Bin'(T, 0)(&sums[0], input[Half])
        output[1] = dct9Bin'(T, 1)(&differences[0], input[Half])
        output[2] = dct9Bin'(T, 2)(&sums[0], input[Half])
        output[3] = dct9Bin'(T, 3)(&differences[0], input[Half])
        output[4] = dct9Bin'(T, 4)(&sums[0], input[Half])
        output[5] = dct9Bin'(T, 5)(&differences[0], input[Half])
        output[6] = dct9Bin'(T, 6)(&sums[0], input[Half])
        output[7] = dct9Bin'(T, 7)(&differences[0], input[Half])
        output[8] = dct9Bin'(T, 8)(&sums[0], input[Half])
    }
    else
    {
        const Half    = N / 2
        const Factors = #run buildCosineReciprocals'Half(cast(f64, N))
        for i in Half
        {
            let first = input[i]
            let last  = input[N - 1 - i]
            output[i]        = first + last
            output[Half + i] = (first - last) * Factors[i]
        }

        dct'(Half, T)(output, input)
        dct'(Half, T)(output + Half, input + Half)

        mergeDctHalves'(N, T)(input, output)
    }
}

// The inverse MDCT is a DCT-IV shifted by N/2 bins. The cosine sum identity gives each
// DCT-IV bin by adding adjacent DCT-II bins of the scaled input, with bin N equal to zero.
#[Swag.Inline]
private func(N: u64, T) scaledCosineTransform(input: const [*] T, stride: u64, bins: [*] T)
{
    const Factors = #run buildCosineReciprocals'N(cast(f64, 2 * N))
    #static if N == 18
    {
        // Apply the input scaling while forming the first DCT-II butterfly.
        const Half = N / 2
        const Pairs = #run buildCosineReciprocals'Half(cast(f64, N))
        var work: [N] T
        for i in Half
        {
            let first = input[i * stride] * Factors[i]
            let j     = N - 1 - i
            let last  = input[j * stride] * Factors[j]
            bins[i]        = first + last
            bins[Half + i] = (first - last) * Pairs[i]
        }

        dct'(Half, T)(bins, &work[0])
        dct'(Half, T)(bins + Half, &work[Half])
        mergeDctHalves'(N, T)(&work[0], bins)
    }
    else
    {
        var scaled: [N] T
        for i in N do
            scaled[i] = input[i * stride] * Factors[i]
        dct'(N, T)(&scaled[0], bins)
    }
}

// A short block combines three overlapping windows.
private func(T) transformShort(input: const [*] T, raw: [*] T)
{
    for window in 3'u64
    {
        var bins: [7] T // Last bin is the zero sentinel.
        scaledCosineTransform'(6, T)(input + window, 3, &bins[0])

        let start = 6 * window + 6
        for i in 3'u64
        {
            let first = bins[i + 3] + bins[i + 4]
            let last  = -(bins[2 - i] + bins[3 - i])
            raw[start + i]      += first * BlockWindow[2, i]
            raw[start + 5 - i]  += -first * BlockWindow[2, 5 - i]
            raw[start + 6 + i]  += last * BlockWindow[2, 6 + i]
            raw[start + 11 - i] += last * BlockWindow[2, 11 - i]
        }
    }
}

// Produce the current block and its saved overlap directly from the long transform's
// symmetric bins. The short transform accumulates its three windows before adding overlap.
private func(T) transformOverlap(input: [*] T, overlap: [*] T, blockType: u32)
{
    // Overlap stores a row of 32 subbands for each time slot.
    const Stride = 32 * #sizeof(f32) / #sizeof(T)
    if blockType == 2
    {
        var raw: [36] T
        transformShort'T(input, &raw[0])
        for i in 18'u64
        {
            input[i]            = raw[i] + overlap[i * Stride]
            overlap[i * Stride] = raw[18 + i]
        }

        return
    }

    // The extra zero bin completes the adjacent-bin sum at the end of the DCT-II.
    var bins: [19] T
    scaledCosineTransform'(18, T)(input, 1, &bins[0])
    for i in 9'u64
    {
        let first  = bins[9 + i] + bins[10 + i]
        let last   = -(bins[8 - i] + bins[9 - i])
        let mirror = 17 - i
        input[i]                 = first * BlockWindow[blockType, i] + overlap[i * Stride]
        input[mirror]            = -first * BlockWindow[blockType, mirror] + overlap[mirror * Stride]
        overlap[i * Stride]      = last * BlockWindow[blockType, 18 + i]
        overlap[mirror * Stride] = last * BlockWindow[blockType, 18 + mirror]
    }
}

private func inverseTransform(lines: *Granule576, overlap: *SubbandOverlap, subband: u32, blockType: u32)
{
    let base = cast(u64, subband) * 18
    transformOverlap'f32(&lines[][base], &overlap[][0, subband], blockType)
}

// Vector lanes hold the same time or frequency slot in four adjacent subbands.
// Their overlap is already contiguous. Each subband's time samples remain contiguous
// for the polyphase pass that follows.
private func inverseTransform4(lines: *Granule576, overlap: *SubbandOverlap, subband, blockType: u32)
{
    using Math.Simd
    let base = cast(u64, subband) * 18
    var input: [18] F32x4

    // Four contiguous time slots per subband form a tile to transpose into SIMD lanes.
    for group in 4'u64
    {
        let slot = group * 4
        let at   = base + slot
        var rows: [4] U32x4 = [
            cast #bit(U32x4, load(&lines[][at])),
            cast #bit(U32x4, load(&lines[][at + 18])),
            cast #bit(U32x4, load(&lines[][at + 36])),
            cast #bit(U32x4, load(&lines[][at + 54]))]
        transpose4x4(&rows)
        for lane in 4'u64 do
            input[slot + lane] = cast #bit(F32x4, rows[lane])
    }

    // Read slots 14 to 17 together and use only the last two columns.
    let tail = cast(const [*] f32, &lines[][base + 14])
    let row0 = cast #bit(U32x4, load(tail))
    let row1 = cast #bit(U32x4, load(tail + 18))
    let row2 = cast #bit(U32x4, load(tail + 36))
    let row3 = cast #bit(U32x4, load(tail + 54))
    let pair01 = cast #bit(U64x2, Swag.vecInterleaveHi(row0, row1))
    let pair23 = cast #bit(U64x2, Swag.vecInterleaveHi(row2, row3))
    input[16] = cast #bit(F32x4, Swag.vecInterleaveLo(pair01, pair23))
    input[17] = cast #bit(F32x4, Swag.vecInterleaveHi(pair01, pair23))

    transformOverlap'F32x4(&input[0], cast([*] F32x4, &overlap[][0, subband]), blockType)

    // Transpose back after windowing and overlap so synthesis can read continuous time slots.
    for group in 4'u64
    {
        let slot = group * 4
        let at   = base + slot
        var rows: [4] U32x4 = [
            cast #bit(U32x4, input[slot]), cast #bit(U32x4, input[slot + 1]),
            cast #bit(U32x4, input[slot + 2]), cast #bit(U32x4, input[slot + 3])]
        transpose4x4(&rows)
        store(&lines[][at], cast #bit(F32x4, rows[0]))
        store(&lines[][at + 18], cast #bit(F32x4, rows[1]))
        store(&lines[][at + 36], cast #bit(F32x4, rows[2]))
        store(&lines[][at + 54], cast #bit(F32x4, rows[3]))
    }

    let slot16 = cast #bit(U32x4, input[16])
    let slot17 = cast #bit(U32x4, input[17])
    let subbands01 = cast #bit(U64x2, Swag.vecInterleaveLo(slot16, slot17))
    let subbands23 = cast #bit(U64x2, Swag.vecInterleaveHi(slot16, slot17))
    let output = cast([*] u64, &lines[][base + 16])
    output[0]  = subbands01[0]
    output[9]  = subbands01[1]
    output[18] = subbands23[0]
    output[27] = subbands23[1]
}

// Encoder low-pass filters often leave the top subbands identically zero. Only
// the preceding window contributes there, up to the previous overlap bound.
// Return the exclusive upper bound of the current spectrum for the next granule.
func inverseTransformBands(lines: *Granule576, overlap: *SubbandOverlap, start, end, blockType: u32, overlapEnd = 32'u32)->u32
{
    using Math.Simd
    var active = end
    while active > start
    {
        let base = cast(u64, (active - 1)) * 18
        let data = cast(const [*] u32, &lines[][base])
        let bits = (load(data) | load(data + 4) | load(data + 8) | load(data + 12)) & 0x7FFFFFFF'u32
        if anyTrue(bits != splat(0'u32)) or lines[][base + 16] != 0 or lines[][base + 17] != 0 do
            break
        active -= 1
    }

    var subband = start
    while subband + 4 <= end and subband < active
    {
        inverseTransform4(lines, overlap, subband, blockType)
        subband += 4
    }

    while subband < active
    {
        inverseTransform(lines, overlap, subband, blockType)
        subband += 1
    }

    // Above the previous overlap bound the untouched spectral lines are already zero.
    let drainEnd = Math.min(end, overlapEnd)
    while subband < drainEnd
    {
        let base = cast(u64, subband) * 18
        for i in 18'u64
        {
            lines[][base + i]  = overlap[][i, subband]
            overlap[][i, subband] = 0
        }

        subband += 1
    }

    return active > start ? active : 0
}

// Negates every second sample of every second subband, which is what puts the filter bank input
// back in phase after the inverse transform.
func invertFrequencies(lines: *Granule576, end: u32)
{
    var subband = 1'u64
    while subband < end
    {
        let base  = subband * 18
        var index = 1'u64
        while index < 18
        {
            lines[][base + index] = -lines[][base + index]
            index += 2
        }

        subband += 2
    }
}

// Samples i and 32-i use the same DCT bins. Their even-delay bins have opposite
// signs, so the second window can carry that reflection in its coefficients.
private func buildMirroredWeights()->[2, 16, 4] Math.Simd.F32x4
{
    var weights: #returntype
    for tap in 16'u64
    {
        let sign = (tap & 1) == 0 ? -1'f32 : 1'f32
        for group in 4'u64
        {
            var left, right: [4] f32
            for lane in 4'u64
            {
                let i = group * 4 + lane + 1
                left[lane]  = SynthesisWindow[tap * 32 + i]
                right[lane] = SynthesisWindow[tap * 32 + 32 - i] * sign
            }

            weights[0, tap, group] = cast(Math.Simd.F32x4, left)
            weights[1, tap, group] = cast(Math.Simd.F32x4, right)
        }
    }

    return weights
}

private const MirroredWeights = #run buildMirroredWeights()

#[Swag.Inline]
private func(Tap: u64) addMirroredPair(history: const [*] f32, group: u64, left, right: *Math.Simd.F32x4)
{
    const Even = 2 * Tap * 32
    const Odd  = Even + 32 + 16
    let lane   = group * 4
    let first  = Math.Simd.load(history + Even + lane)
    let second = Math.Simd.load(history + Odd + lane)
    left[]  += first * MirroredWeights[0, 2 * Tap, group]
    left[]  += second * MirroredWeights[0, 2 * Tap + 1, group]
    right[] += first * MirroredWeights[1, 2 * Tap, group]
    right[] += second * MirroredWeights[1, 2 * Tap + 1, group]
}

// Store each DCT bin once for the reflected windows that read this history row.
private func saveSynthesisBins(state: *ChannelState, halves: const [*] f32)
{
    state.filterAt = (state.filterAt + FilterMask) & FilterMask
    let newest = cast([*] f32, &state.filter[state.filterAt, 0])

    // The DCT's even and odd results stay separate until the history write.
    let even = halves
    let odd  = halves + 16 * 4
    for i in 7'u64
    {
        newest[2 * i]     = odd[(8 + i) * 4]
        newest[2 * i + 1] = even[(9 + i) * 4]
    }

    newest[14] = odd[15 * 4]
    newest[15] = 0
    for i in 8'u64
    {
        newest[16 + 2 * i] = -odd[(7 - i) * 4]
        newest[17 + 2 * i] = -even[(7 - i) * 4]
    }

    // The mirrored rows let each 16-tap window read across the wrap.
    if state.filterAt < FilterMirrorRows do
        Memory.copy(&state.filter[state.filterAt + FilterHistory, 0], newest, #sizeof(f32) * 32)

    let first = even[8 * 4]
    state.firstHistory[state.filterAt]                 = first
    state.firstHistory[state.filterAt + FilterHistory] = first
}

private func buildFirstSampleWeights()->[16] f32
{
    var weights: #returntype
    for tap in 16'u64 do
        weights[tap] = (tap & 1) == 0 ? SynthesisWindow[tap * 32] : -SynthesisWindow[tap * 32]
    return weights
}

private const FirstSampleWeights = #run buildFirstSampleWeights()

// Each lane is the first sample of one time slot, ordered newest to oldest.
private func synthesizeFirstSamples(state: const *ChannelState, at: u64)->Math.Simd.F32x4
{
    using Math.Simd
    let newest = cast(const [*] f32, &state.firstHistory[at])
    var samples: F32x4
    for tap in 16'u64 do
        samples += load(newest + tap) * FirstSampleWeights[tap]
    return samples
}

private func synthesizeBlock(state: const *ChannelState, at: u64, destination: [*] f32)
{
    using Math.Simd
    const Reverse = cast(U32x4, [3'u32, 2, 1, 0])
    let history = cast(const [*] f32, &state.filter[at, 0])
    for group in 4'u64
    {
        var left, right: F32x4
        addMirroredPair'0(history, group, &left, &right)
        addMirroredPair'1(history, group, &left, &right)
        addMirroredPair'2(history, group, &left, &right)
        addMirroredPair'3(history, group, &left, &right)
        addMirroredPair'4(history, group, &left, &right)
        addMirroredPair'5(history, group, &left, &right)
        addMirroredPair'6(history, group, &left, &right)
        addMirroredPair'7(history, group, &left, &right)

        // The final stores meet at sample 16. Its even-delay bin is zero,
        // so both lanes produce the same sample.
        store(destination + 1 + group * 4, left)
        store(destination + 28 - group * 4, permute(right, Reverse))
    }
}

// The four slots use the same window coefficients with consecutive history rows.
private func synthesizeBlockFour(state: const *ChannelState, at: u64, destination: [*] f32)
{
    using Math.Simd
    const Reverse = cast(U32x4, [3'u32, 2, 1, 0])
    let history = cast(const [*] f32, &state.filter[at, 0])
    for group in 4'u64
    {
        var aLeft, bLeft, cLeft, dLeft: F32x4
        var aRight, bRight, cRight, dRight: F32x4
        let lane = group * 4
        let column = history + lane
        var evenOlder = load(column + 32)
        var evenNewer = load(column)
        var oddOlder  = load(column + 80)
        var oddNewer  = load(column + 48)
        for pair in 8'u64
        {
            let tap  = 2 * pair
            let even = column + pair * 64
            let odd  = even + 48

            // This tap's later two slots were the first two two taps earlier.
            let leftEven  = MirroredWeights[0, tap, group]
            let rightEven = MirroredWeights[1, tap, group]
            cLeft  += evenOlder * leftEven
            cRight += evenOlder * rightEven
            dLeft  += evenNewer * leftEven
            dRight += evenNewer * rightEven
            evenOlder = load(even + 96)
            evenNewer = load(even + 64)
            aLeft  += evenOlder * leftEven
            aRight += evenOlder * rightEven
            bLeft  += evenNewer * leftEven
            bRight += evenNewer * rightEven

            let leftOdd  = MirroredWeights[0, tap + 1, group]
            let rightOdd = MirroredWeights[1, tap + 1, group]
            cLeft  += oddOlder * leftOdd
            cRight += oddOlder * rightOdd
            dLeft  += oddNewer * leftOdd
            dRight += oddNewer * rightOdd
            oddOlder = load(odd + 96)
            oddNewer = load(odd + 64)
            aLeft  += oddOlder * leftOdd
            aRight += oddOlder * rightOdd
            bLeft  += oddNewer * leftOdd
            bRight += oddNewer * rightOdd
        }

        let left  = destination + 1 + lane
        let right = destination + 28 - lane
        store(left,       aLeft)
        store(right,      permute(aRight, Reverse))
        store(left + 32,  bLeft)
        store(right + 32, permute(bRight, Reverse))
        store(left + 64,  cLeft)
        store(right + 64, permute(cRight, Reverse))
        store(left + 96,  dLeft)
        store(right + 96, permute(dRight, Reverse))
    }
}

// The opposite subbands form the first DCT-II butterfly. Load them directly into
// the two half-size transforms instead of staging a copy of all 32 subbands.
#[Swag.Inline]
private func polyphaseHalves(lines: const *Granule576, start: u64, halves: [*] Math.Simd.F32x4)
{
    using Math.Simd
    const Outer = #run buildCosineReciprocals'16(32'f64)
    const Inner = #run buildCosineReciprocals'8(16'f64)
    var quarters: [4, 8] F32x4
    for i in 8'u64
    {
        let j     = 15 - i
        let low   = load(&lines[][i * 18 + start])
        let high  = load(&lines[][(31 - i) * 18 + start])
        let otherLow  = load(&lines[][j * 18 + start])
        let otherHigh = load(&lines[][(31 - j) * 18 + start])
        let even     = low + high
        let odd      = (low - high) * Outer[i]
        let evenPair = otherLow + otherHigh
        let oddPair  = (otherLow - otherHigh) * Outer[j]
        quarters[0, i] = even + evenPair
        quarters[1, i] = (even - evenPair) * Inner[i]
        quarters[2, i] = odd + oddPair
        quarters[3, i] = (odd - oddPair) * Inner[i]
    }

    var partial: [8] F32x4
    writeDct8'(F32x4, 2)(&quarters[0, 0], halves)
    writeDct8'(F32x4, 1)(&quarters[1, 0], &partial[0])
    for i in 7'u64 do
        halves[2 * i + 1] = partial[i] + partial[i + 1]
    halves[15] = partial[7]

    // The following window reads neighboring sums of the odd half. Combine
    // them directly from its two DCT-II branches after computing both.
    writeDct8'(F32x4, 1)(&quarters[2, 0], &quarters[0, 0])
    writeDct8'(F32x4, 1)(&quarters[3, 0], &partial[0])
    for i in 7'u64
    {
        let odd = partial[i] + partial[i + 1]
        halves[16 + 2 * i] = quarters[0, i] + odd
        halves[17 + 2 * i] = odd + quarters[0, i + 1]
    }
    halves[30] = quarters[0, 7] + partial[7]
    halves[31] = partial[7]
}

// Turns the 32 by 18 subband samples of one granule into 576 output samples.
//
// Each vector lane holds a different time slot. The last four-slot input overlaps
// the previous group by two slots, so the widest read ends at the last sample.
func synthesizeGranule(state: *ChannelState, lines: const *Granule576, destination: [*] f32)
{
    for group in 5'u64
    {
        let first = group * 4
        let start = Math.min(first, 14)
        var halves: [32] Math.Simd.F32x4
        polyphaseHalves(lines, start, &halves[0])

        let values = cast(const [*] f32, &halves[0])
        for lane in first - start until 4'u64 do
            saveSynthesisBins(state, values + lane)

        // Keep all sixteen taps of the earliest slot after saving the later three.
        let at     = state.filterAt
        let starts = synthesizeFirstSamples(state, at)
        let pcm    = destination + first * 32
        if first == start
        {
            pcm[0]  = starts[3]
            pcm[32] = starts[2]
            pcm[64] = starts[1]
            pcm[96] = starts[0]
            synthesizeBlockFour(state, at, pcm)
        }
        else
        {
            pcm[0]  = starts[1]
            pcm[32] = starts[0]
            synthesizeBlock(state, (at + 1) & FilterMask, destination + first * 32)
            synthesizeBlock(state, at, destination + (first + 1) * 32)
        }
    }
}
