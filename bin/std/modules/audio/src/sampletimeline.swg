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
// starts sample zero unless an origin was provided or `advanceTo` established one. Later blocks
// may leave a gap or overlap the written prefix; the placement tells the caller how much silence
// to insert or how many leading frames to discard. All counts refer to sample frames, regardless
// of channel count. State has constant size.
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
        hasOrigin:     bool
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

    // Creates a timeline starting at `originTick` on the monotonic clock.
    //
    // A first block captured later reports its initial silence. Use the same origin as a video
    // frame pacer to preserve the initial offset between sound and picture.
    func createWithOrigin(sampleRate: u32, clockFrequency: u64, originTick: u64, tolerance: u32 = 0)->SampleTimeline fail
    {
        var result = try create(sampleRate, clockFrequency, tolerance)
        result.firstTick    = originTick
        result.previousTick = originTick
        result.hasOrigin    = true
        return result
    }

    // Returns the end of the placed audio in sample frames.
    mtd const sampleEnd()->u64 => .sampleEndValue

    // Extends the timeline with silence up to `tick` and returns the frames to write.
    //
    // This also covers a source that disappears before recording stops. Without an explicit
    // origin, the first call establishes sample zero at `tick`. Timestamps must not move
    // backwards; an invalid or overflowing timestamp leaves the timeline unchanged.
    mtd advanceTo(tick: u64)->u64 fail
    {
        if not .hasBlock and not .hasOrigin
        {
            .firstTick    = tick
            .previousTick = tick
            .hasBlock     = true
            return 0
        }

        let target  = try .targetAt(tick)
        let silence = target > .sampleEndValue ? target - .sampleEndValue : 0
        .sampleEndValue += silence
        .previousTick    = tick
        .hasBlock        = true
        return silence
    }

    // Places a nonempty block and advances the timeline if it contains new samples.
    //
    // Timestamps must not move backwards. Rounding is to the nearest sample, with midpoint
    // rounding upward. An invalid or overflowing block leaves the timeline unchanged.
    mtd place(tick: u64, frameCount: u64)->SamplePlacement fail
    {
        if not frameCount do
            fail BadParameterError{"sample timeline blocks must contain frames"}
        if not .hasBlock and not .hasOrigin
        {
            .firstTick      = tick
            .previousTick   = tick
            .sampleEndValue = frameCount
            .hasBlock       = true
            return SamplePlacement{0, 0, 0, frameCount}
        }
        let target = try .targetAt(tick)
        if frameCount > Swag.U64.Max - target do
            fail OverflowError{"sample timeline block end overflows"}

        let silence   = target > .sampleEndValue ? target - .sampleEndValue : 0
        let discarded = target < .sampleEndValue ? Math.min(.sampleEndValue - target, frameCount) : 0
        let accepted  = frameCount - discarded
        let start     = Math.max(target, .sampleEndValue)
        .sampleEndValue = start + accepted
        .previousTick   = tick
        .hasBlock       = true
        return SamplePlacement{start, silence, discarded, accepted}
    }

    private mtd const targetAt(tick: u64)->u64 fail
    {
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
        if .hasBlock
        {
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
        }
        return target
    }
}
