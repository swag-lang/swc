#global public

using Core, Core.Errors

// Describes how a captured PCM block joins a continuous sample timeline.
struct SamplePlacement
{
    public startSample:      u64 // Write position after any silence; also the current end if empty.
    public silenceFrames:    u64 // Silent frames to write before the block.
    public discardedFrames:  u64 // Leading captured frames already covered by earlier blocks.
    public acceptedFrames:   u64 // Captured frames to write after discarding the overlap.
}

// Places timestamped PCM blocks on a sample clock without retaining audio data.
//
// The timestamp of each block names its first sample on one monotonic clock. The first block
// starts sample zero. Later blocks may leave a gap or overlap the written prefix; the placement
// tells the caller how much silence to insert or how many leading frames to discard. All counts
// refer to sample frames, regardless of channel count. State has constant size.
#[Swag.Opaque]
struct SampleTimeline
{
    internal
    {
        sampleRate:     u32
        clockFrequency: u64
        tolerance:      u32
        firstTick:      u64
        previousTick:   u64
        sampleEndValue: u64
        hasBlock:       bool
    }
}

impl SampleTimeline
{
    // Creates a timeline for `sampleRate` frames per second and a monotonic clock frequency.
    //
    // The product of both rates must fit in 64 bits for exact fractional conversion.
    // `tolerance` snaps timestamp differences of at most this many sample frames to the
    // continuous write position. Zero preserves exact gaps and overlaps.
    func create(sampleRate: u32, clockFrequency: u64, tolerance: u32 = 0)->SampleTimeline fail
    {
        if not sampleRate or not clockFrequency or clockFrequency > Swag.U64.Max / sampleRate do
            fail BadParameterError{"sample timeline needs representable positive clock rates"}
        return SampleTimeline{sampleRate, clockFrequency, tolerance}
    }

    // Returns the end of the placed audio in sample frames.
    mtd const sampleEnd()->u64 => .sampleEndValue

    // Places a nonempty block and advances the timeline if it contains new samples.
    //
    // Timestamps must not move backwards. Rounding is to the nearest sample, with midpoint
    // rounding upward. An invalid or overflowing block leaves the timeline unchanged.
    mtd place(tick: u64, frameCount: u64)->SamplePlacement fail
    {
        if not frameCount do
            fail BadParameterError{"sample timeline blocks must contain frames"}
        if not .hasBlock
        {
            .firstTick      = tick
            .previousTick   = tick
            .sampleEndValue = frameCount
            .hasBlock       = true
            return SamplePlacement{0, 0, 0, frameCount}
        }
        if tick < .previousTick do
            fail BadParameterError{"sample timeline timestamps must not move backwards"}

        let elapsed      = tick - .firstTick
        let wholeSeconds = elapsed / .clockFrequency
        if wholeSeconds > Swag.U64.Max / .sampleRate do
            fail OverflowError{"sample timeline position overflows"}
        let wholeSamples = wholeSeconds * .sampleRate
        let fraction     = (elapsed % .clockFrequency) * .sampleRate
        let rounded      = fraction / .clockFrequency +
                           cast(u64, fraction % .clockFrequency >=
                                      .clockFrequency / 2 + .clockFrequency % 2)
        if rounded > Swag.U64.Max - wholeSamples do
            fail OverflowError{"sample timeline position overflows"}
        var target = wholeSamples + rounded
        if target >= .sampleEndValue
        {
            if target - .sampleEndValue <= .tolerance do
                target = .sampleEndValue
        }
        else
        {
            if .sampleEndValue - target <= .tolerance do
                target = .sampleEndValue
        }
        if frameCount > Swag.U64.Max - target do
            fail OverflowError{"sample timeline block end overflows"}

        let silence   = target > .sampleEndValue ? target - .sampleEndValue : 0
        let discarded = target < .sampleEndValue ? Math.min(.sampleEndValue - target, frameCount) : 0
        let accepted  = frameCount - discarded
        let start     = Math.max(target, .sampleEndValue)
        .sampleEndValue = start + accepted
        .previousTick   = tick
        return SamplePlacement{start, silence, discarded, accepted}
    }
}
