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
        Memory.set(cast(*void) &.overlap[0, 0], 0, #sizeof(f32) * 32 * 18)
        Memory.set(cast(*void) &.filter[0], 0, #sizeof(f32) * 1024)
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
    var scratch: Granule576 = undefined
    var source              = firstLine
    var band                = cast(u64) firstBand
    var written             = 0'u64

    while band < bands.count
    {
        let width = cast(u32) bands[band]
        if !width do
            break
        band += 3

        if source + width * 3 > 576 do
            break
        for index in width
        {
            for window in 3'u32 do
                scratch[written + cast(u64) (index * 3 + window)] = lines[][source + window * width + index]
        }

        written += cast(u64) width * 3
        source  += width * 3
    }

    for index in written do
        lines[][cast(u64) firstLine + index] = scratch[index]
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
        let boundary = cast(u64) subband * 18
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

// The inverse transform of one subband, windowed, and added to what the previous granule left.
//
// `blockType` selects the window: 0 normal, 1 start, 2 three short blocks, 3 stop. A short block
// is three six-point transforms whose windows overlap each other six samples apart inside the
// thirty-six sample result, before the result overlaps its predecessor.
func inverseTransform(lines: *Granule576, overlap: *[32, 18] f32, subband: u32, blockType: u32)
{
    let base            = cast(u64) subband * 18
    var input: [18] f32 = undefined
    for index in 18'u64 do
        input[index] = lines[][base + index]

    var raw: [36] f32 = undefined
    if blockType == 2
    {
        for index in 36'u64 do
            raw[index] = 0
        for window in 3'u64
        {
            for p in 12'u64
            {
                var sum = 0'f32
                for m in 6'u64 do
                    sum += input[window + 3 * m] * Imdct6[p, m]
                raw[6 * window + p + 6] += sum * BlockWindow[2, p]
            }
        }
    }
    else
    {
        for p in 36'u64
        {
            var sum = 0'f32
            for m in 18'u64 do
                sum += input[m] * Imdct18[p, m]
            raw[p] = sum * BlockWindow[blockType, p]
        }
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
            index                 += 2
        }

        subband += 2
    }
}

// Turns the 32 by 18 subband samples of one granule into 576 output samples.
//
// This is the polyphase filter bank stated in the standard: matrix the 32 subband samples of one
// block into 64, push them onto a delay line 1024 long, gather 512 of it, window by the normative
// 512-tap prototype, and fold that down to 32 samples. The delay line rotates instead of being
// shifted, which is the same thing and does not move 960 floats per block.
func synthesizeGranule(state: *ChannelState, lines: const *Granule576, destination: [*] f32, stride: u64)
{
    var gathered: [512] f32 = undefined

    for block in 18'u64
    {
        state.filterAt = (state.filterAt + 1024 - 64) & 1023
        let at = cast(u64) state.filterAt

        for i in 64'u64
        {
            var sum = 0'f32
            for j in 32'u64 do
                sum += SynthesisMatrix[i, j] * lines[][j * 18 + block]
            state.filter[(at + i) & 1023] = sum
        }

        for i in 8'u64
        {
            for j in 32'u64
            {
                gathered[i * 64 + j]      = state.filter[(at + i * 128 + j) & 1023]
                gathered[i * 64 + 32 + j] = state.filter[(at + i * 128 + 96 + j) & 1023]
            }
        }

        for i in 32'u64
        {
            var sum = 0'f32
            for j in 16'u64
            {
                let slot = j * 32 + i
                sum += gathered[slot] * SynthesisWindow[slot]
            }

            destination[(block * 32 + i) * stride] = sum
        }
    }
}
