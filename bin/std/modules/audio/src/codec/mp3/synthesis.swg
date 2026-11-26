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

// What one channel carries from one granule to the next.
//
// The inverse transform of a granule overlaps the one before it, and the filter bank looks back
// over the last sixteen blocks it produced, so a channel cannot be decoded from its own granule
// alone. A seek resets both.
struct ChannelState
{
    overlap:  SubbandOverlap          // Second half of the previous inverse transform, grouped by time slot.
    filter:   [FilterHistory, 33] f32 // Even and odd bins for paired samples, plus the unpaired first sample.
    filterAt: u64                     // Newest block of the delay line.
}

impl ChannelState
{
    // Restores the state a decode starts from, which is what a seek needs.
    mtd reset()
    {
        Memory.set(cast(*void, &.overlap[0, 0]), 0, #sizeof(f32) * 32 * 18)
        Memory.set(cast(*void, &.filter[0, 0]), 0, #sizeof(f32) * FilterHistory * 33)
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
    elif N == 3
    {
        let ends = input[0] + input[2]
        output[0] = ends + input[1]
        output[1] = (input[0] - input[2]) * 0.866025404
        output[2] = ends * 0.5 - input[1]
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

        for i in Half - 1
        {
            output[2 * i]     = input[i]
            output[2 * i + 1] = input[Half + i] + input[Half + i + 1]
        }

        output[N - 2] = input[Half - 1]
        output[N - 1] = input[N - 1]
    }
}

// The inverse MDCT is a DCT-IV shifted by N/2 bins. The cosine sum identity gives each
// DCT-IV bin by adding adjacent DCT-II bins of the scaled input, with bin N equal to zero.
#[Swag.Inline]
private func(N: u64, T) scaledCosineTransform(input: const [*] T, stride: u64, bins: [*] T)
{
    const Factors = #run buildCosineReciprocals'N(cast(f64, 2 * N))
    var scaled: [N] T
    for i in N do
        scaled[i] = input[i * stride] * Factors[i]
    dct'(N, T)(&scaled[0], bins)
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

    for i in 16 until 18'u64
    {
        let at = base + i
        input[i] = cast(F32x4, [lines[][at], lines[][at + 18], lines[][at + 36], lines[][at + 54]])
    }

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

    for i in 16 until 18'u64
    {
        let at     = base + i
        let sample = input[i]
        lines[][at]      = sample[0]
        lines[][at + 18] = sample[1]
        lines[][at + 36] = sample[2]
        lines[][at + 54] = sample[3]
    }
}

// Encoder low-pass filters often leave the top subbands identically zero. Only
// the preceding window contributes there, so copy the overlap and clear it.
func inverseTransformBands(lines: *Granule576, overlap: *SubbandOverlap, start, end, blockType: u32)
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

    for band in subband until end
    {
        let base = cast(u64, band) * 18
        for i in 18'u64
        {
            lines[][base + i]  = overlap[][i, band]
            overlap[][i, band] = 0
        }
    }
}

// Negates every second sample of every second subband, which is what puts the filter bank input
// back in phase after the inverse transform.
func invertFrequencies(lines: *Granule576)
{
    var subband = 1'u64
    while subband < 32
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
private func(Tap: u64) addMirroredPair(state: const *ChannelState, at, group: u64, left, right: *Math.Simd.F32x4)
{
    let even   = (at + 2 * Tap) & FilterMask
    let odd    = (even + 1) & FilterMask
    let lane   = group * 4
    let first  = Math.Simd.load(&state.filter[even, lane])
    let second = Math.Simd.load(&state.filter[odd, 16 + lane])
    left[]  += first * MirroredWeights[0, 2 * Tap, group]
    left[]  += second * MirroredWeights[0, 2 * Tap + 1, group]
    right[] += first * MirroredWeights[1, 2 * Tap, group]
    right[] += second * MirroredWeights[1, 2 * Tap + 1, group]
}

// Store each DCT bin once for the reflected windows that read this history row.
private func saveSynthesisBins(state: *ChannelState, bins: const [*] f32)
{
    state.filterAt = (state.filterAt + FilterMask) & FilterMask
    let newest = cast([*] f32, &state.filter[state.filterAt, 0])

    for i in 15'u64 do
        newest[i] = bins[(17 + i) * 4]
    newest[15] = 0
    for i in 16'u64 do
        newest[16 + i] = -bins[(15 - i) * 4]
    newest[32] = bins[16 * 4]
}

private func synthesizeFirstSample(state: const *ChannelState, at: u64)->f32
{
    var firstSample: f32
    for tap in 8'u64
    {
        let even = (at + 2 * tap) & FilterMask
        let odd  = (even + 1) & FilterMask
        firstSample += state.filter[even, 32] * SynthesisWindow[tap * 64]
        firstSample += -state.filter[odd, 32] * SynthesisWindow[tap * 64 + 32]
    }

    return firstSample
}

private func synthesizeBlock(state: const *ChannelState, at: u64, destination: [*] f32)
{
    using Math.Simd
    const Reverse = cast(U32x4, [3'u32, 2, 1, 0])
    destination[0] = synthesizeFirstSample(state, at)
    for group in 4'u64
    {
        var left, right: F32x4
        addMirroredPair'0(state, at, group, &left, &right)
        addMirroredPair'1(state, at, group, &left, &right)
        addMirroredPair'2(state, at, group, &left, &right)
        addMirroredPair'3(state, at, group, &left, &right)
        addMirroredPair'4(state, at, group, &left, &right)
        addMirroredPair'5(state, at, group, &left, &right)
        addMirroredPair'6(state, at, group, &left, &right)
        addMirroredPair'7(state, at, group, &left, &right)

        // The final stores meet at sample 16. Its even-delay bin is zero,
        // so both lanes produce the same sample.
        store(destination + 1 + group * 4, left)
        store(destination + 28 - group * 4, permute(right, Reverse))
    }
}

// Windows two time slots apart share fourteen rows and the same tap parity.
#[Swag.Inline]
private func(Tap: u64) addSharedMirroredPair(state: const *ChannelState, at, group: u64, left, right, laterLeft, laterRight: *Math.Simd.F32x4)
{
    let even   = (at + 2 * Tap) & FilterMask
    let odd    = (even + 1) & FilterMask
    let lane   = group * 4
    let first  = Math.Simd.load(&state.filter[even, lane])
    let second = Math.Simd.load(&state.filter[odd, 16 + lane])
    left[]       += first * MirroredWeights[0, 2 * Tap, group]
    left[]       += second * MirroredWeights[0, 2 * Tap + 1, group]
    right[]      += first * MirroredWeights[1, 2 * Tap, group]
    right[]      += second * MirroredWeights[1, 2 * Tap + 1, group]
    laterLeft[]  += first * MirroredWeights[0, 2 * Tap + 2, group]
    laterLeft[]  += second * MirroredWeights[0, 2 * Tap + 3, group]
    laterRight[] += first * MirroredWeights[1, 2 * Tap + 2, group]
    laterRight[] += second * MirroredWeights[1, 2 * Tap + 3, group]
}

private func synthesizeBlockPair(state: const *ChannelState, at: u64, destination: [*] f32)
{
    using Math.Simd
    const Reverse = cast(U32x4, [3'u32, 2, 1, 0])
    let laterAt = (at + FilterMask - 1) & FilterMask
    destination[0]  = synthesizeFirstSample(state, at)
    destination[64] = synthesizeFirstSample(state, laterAt)
    for group in 4'u64
    {
        var left, right, laterLeft, laterRight: F32x4
        addMirroredPair'0(state, laterAt, group, &laterLeft, &laterRight)
        addSharedMirroredPair'0(state, at, group, &left, &right, &laterLeft, &laterRight)
        addSharedMirroredPair'1(state, at, group, &left, &right, &laterLeft, &laterRight)
        addSharedMirroredPair'2(state, at, group, &left, &right, &laterLeft, &laterRight)
        addSharedMirroredPair'3(state, at, group, &left, &right, &laterLeft, &laterRight)
        addSharedMirroredPair'4(state, at, group, &left, &right, &laterLeft, &laterRight)
        addSharedMirroredPair'5(state, at, group, &left, &right, &laterLeft, &laterRight)
        addSharedMirroredPair'6(state, at, group, &left, &right, &laterLeft, &laterRight)
        addMirroredPair'7(state, at, group, &left, &right)
        store(destination + 1 + group * 4, left)
        store(destination + 28 - group * 4, permute(right, Reverse))
        store(destination + 65 + group * 4, laterLeft)
        store(destination + 92 - group * 4, permute(laterRight, Reverse))
    }
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
        var input, bins: [32] Math.Simd.F32x4
        for i in 32'u64 do
            input[i] = Math.Simd.load(&lines[][i * 18 + start])
        dct'(32, Math.Simd.F32x4)(&input[0], &bins[0])

        let values = cast(const [*] f32, &bins[0])
        for lane in first - start until 4'u64 do
            saveSynthesisBins(state, values + lane)

        // Keep all sixteen taps of the earliest slot after saving the later three.
        let at = state.filterAt
        if first == start
        {
            synthesizeBlockPair(state, (at + 3) & FilterMask, destination + first * 32)
            synthesizeBlockPair(state, (at + 2) & FilterMask, destination + (first + 1) * 32)
        }
        else
        {
            synthesizeBlock(state, (at + 1) & FilterMask, destination + first * 32)
            synthesizeBlock(state, at, destination + (first + 1) * 32)
        }
    }
}
