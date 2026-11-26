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
alias Granule576 = [576] f32

// What one channel carries from one granule to the next.
//
// The inverse transform of a granule overlaps the one before it, and the filter bank looks back
// over the last sixteen blocks it produced, so a channel cannot be decoded from its own granule
// alone. A seek resets both.
struct ChannelState
{
    overlap:  [32, 18] f32     // Second half of the previous inverse transform, per subband.
    filter:   [1024] f32       // The filter bank's delay line, addressed through `filterAt`.
    filterAt: u32              // Where the newest block of 64 starts in `filter`.
}

impl ChannelState
{
    // Restores the state a decode starts from, which is what a seek needs.
    mtd reset()
    {
        Memory.set(cast(*void, &.overlap[0, 0]), 0, #sizeof(f32) * 32 * 18)
        Memory.set(cast(*void, &.filter[0]), 0, #sizeof(f32) * 1024)
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
    for subband in 1 until subbandCount
    {
        let boundary = cast(u64, subband) * 18
        for index in 8'u64
        {
            let below = boundary - 1 - index
            let above = boundary + index
            let a     = lines[][below]
            let b     = lines[][above]
            lines[][below] = a * AliasCs[index] - b * AliasCa[index]
            lines[][above] = b * AliasCs[index] + a * AliasCa[index]
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

// Unnormalized DCT-II: X[k] = sum_i x[i] cos(pi*(i+1/2)*k/N).
//
// Pairing opposite input samples separates even and odd outputs. Lee's half-angle factor
// reduces each half to a DCT-II again. The only odd lengths reached are the MP3 IMDCT
// leaves of three and nine points.
private func(N: u64) dct(input: const [*] f32, output: [*] f32)
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
        const Half   = N / 2
        const Matrix = #run buildDct9Matrix()
        var sums, differences: [Half] f32
        for i in Half
        {
            let first = input[i]
            let last  = input[N - 1 - i]
            sums[i]        = first + last
            differences[i] = first - last
        }

        for k in N
        {
            let odd   = (k & 1) != 0
            let pairs = odd ? &differences : &sums
            var sum   = odd ? 0'f32 : ((k & 2) != 0 ? -input[Half] : input[Half])
            for i in Half do
                sum += pairs[][i] * Matrix[k, i]
            output[k] = sum
        }
    }
    else
    {
        const Half    = N / 2
        const Factors = #run buildCosineReciprocals'Half(cast(f64, N))
        var sums, differences, even, odd: [Half] f32
        for i in Half
        {
            let first = input[i]
            let last  = input[N - 1 - i]
            sums[i]        = first + last
            differences[i] = (first - last) * Factors[i]
        }

        dct'Half(&sums[0], &even[0])
        dct'Half(&differences[0], &odd[0])

        for i in Half - 1
        {
            output[2 * i]     = even[i]
            output[2 * i + 1] = odd[i] + odd[i + 1]
        }

        output[N - 2] = even[Half - 1]
        output[N - 1] = odd[Half - 1]
    }
}

// The inverse MDCT is a DCT-IV shifted by N/2 bins. The cosine sum identity gives each
// DCT-IV bin by adding adjacent DCT-II bins of the scaled input, with bin N equal to zero.
// Symmetry then expands the shifted bins to the two halves of the time-domain block.
private func(N: u64) inverseMdct(input: const [*] f32, stride: u64, output: [*] f32)
{
    const Factors = #run buildCosineReciprocals'N(cast(f64, 2 * N))
    var scaled, bins: [N] f32
    for i in N do
        scaled[i] = input[i * stride] * Factors[i]
    dct'N(&scaled[0], &bins[0])

    for i in N - 1 do
        bins[i] += bins[i + 1]

    const Half = N / 2
    for i in Half
    {
        let first = bins[i + Half]
        let last  = -bins[Half - 1 - i]
        output[i]             = first
        output[N - 1 - i]     = -first
        output[N + i]         = last
        output[2 * N - 1 - i] = last
    }
}

// The inverse transform of one subband, windowed, and added to what the previous granule left.
//
// `blockType` selects the window: 0 normal, 1 start, 2 three short blocks, 3 stop. A short block
// is three six-point transforms whose windows overlap each other six samples apart inside the
// thirty-six sample result, before the result overlaps its predecessor.
func inverseTransform(lines: *Granule576, overlap: *[32, 18] f32, subband: u32, blockType: u32)
{
    let base  = cast(u64, subband) * 18
    let input = cast(const [*] f32, &lines[][base])
    var raw: [36] f32

    if blockType == 2
    {
        for window in 3'u64
        {
            var shortBlock: [12] f32
            inverseMdct'6(input + window, 3, &shortBlock[0])
            for i in 12'u64 do
                raw[6 * window + i + 6] += shortBlock[i] * BlockWindow[2, i]
        }
    }
    else
    {
        inverseMdct'18(input, 1, &raw[0])
        for i in 36'u64 do
            raw[i] *= BlockWindow[blockType, i]
    }

    // The first half leaves now, added to what the previous granule kept; the second half waits.
    for index in 18'u64
    {
        lines[][base + index]     = raw[index] + overlap[][subband, index]
        overlap[][subband, index] = raw[18 + index]
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

// Turns the 32 by 18 subband samples of one granule into 576 output samples.
//
// The 64 rows of the polyphase matrix are the 32 DCT-II bins and their reflections.
// Keep the delay line in window order so each multiply reads four adjacent sample lanes.
func synthesizeGranule(state: *ChannelState, lines: const *Granule576, destination: [*] f32)
{
    for block in 18'u64
    {
        state.filterAt = (state.filterAt + 1024 - 64) & 1023
        let at     = cast(u64, state.filterAt)
        let newest = cast([*] f32, &state.filter[at])

        var input, bins: [32] f32
        for i in 32'u64 do
            input[i] = lines[][i * 18 + block]
        dct'32(&input[0], &bins[0])

        newest[0]  = bins[16]
        newest[16] = 0
        newest[32] = -bins[16]
        newest[48] = -bins[0]
        for i in 1 until 16'u64
        {
            newest[16 - i] = bins[32 - i]
            newest[16 + i] = -bins[32 - i]
            newest[48 - i] = -bins[i]
            newest[48 + i] = -bins[i]
        }

        for group in 8'u64
        {
            let lane = group * 4
            var sum: Math.Simd.F32x4
            for tap in 8'u64
            {
                let filter = (at + tap * 128) & 1023
                let first  = Math.Simd.load(&state.filter[filter + lane])
                let second = Math.Simd.load(&state.filter[((filter + 96) & 1023) + lane])
                let weight = tap * 64 + lane
                sum += first * Math.Simd.load(&SynthesisWindow[weight])
                sum += second * Math.Simd.load(&SynthesisWindow[weight + 32])
            }

            Math.Simd.store(destination + block * 32 + lane, sum)
        }
    }
}
