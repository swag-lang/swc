#global public

using Core, Core.Errors

// One accepted picture on a constant-rate recording timeline.
struct FrameSlot
{
    public index:         u64     // Zero-based frame position since the first accepted picture.
    public decodeTime:    u64     // Start in the recording's video timescale ticks.
    public duration:      u32     // Positive length in video timescale ticks.
    public skippedFrames: u64     // Frame positions missed since the previous accepted picture.
}

// Assigns captured pictures to an exact frame-rate timeline without cumulative rounding.
//
// Input timestamps use one monotonic clock. The first picture starts slot zero; later pictures
// that arrive in an already accepted slot are ignored. A late picture skips whole slots, which
// the caller may count as dropped frames or fill by repeating the previous picture. The pacer
// neither sleeps nor stores pictures. Its state has constant size for long recordings.
#[Swag.Opaque]
struct FramePacer
{
    internal
    {
        rate:           FrameRate
        clockFrequency: u64
        videoTimescale: u32
        firstTick:      u64
        previousTick:   u64
        previousSlot:   u64
        hasOrigin:      bool
        hasPicture:     bool
    }
}

impl FramePacer
{
    // Creates a pacer for `rate` frames per second and a positive monotonic clock frequency.
    //
    // `videoTimescale` is the output MP4 video ticks per second. It must provide at least one
    // tick per frame, including fractional rates such as 30000/1001.
    func create(rate: FrameRate, clockFrequency: u64, videoTimescale: u32)->FramePacer fail
    {
        if not rate.isValid() or not clockFrequency or not videoTimescale do
            fail BadParameterError{"frame pacer needs positive clock and frame rates"}
        let ticksPerFrame = cast(u64, videoTimescale) * rate.denominator()
        let maxDuration   = ticksPerFrame / rate.numerator() +
                            cast(u64, ticksPerFrame % rate.numerator() != 0)
        let divisor = cast(u32, try Math.gcd(rate.numerator(), rate.denominator()))
        let reduced = try FrameRate.create(rate.numerator() / divisor, rate.denominator() / divisor)
        let clockScale = cast(u64, reduced.numerator()) * reduced.denominator()
        if ticksPerFrame < rate.numerator() or
           maxDuration > Swag.U32.Max or
           clockFrequency > Swag.U64.Max / clockScale do
            fail BadParameterError{"frame pacer rate cannot fit its video or monotonic clock"}
        return FramePacer{reduced, clockFrequency, videoTimescale}
    }

    // Creates a pacer whose recording timeline starts at `originTick`.
    //
    // A first picture captured later enters its actual frame slot and reports the missing
    // earlier slots. Use the same origin as a sound timeline to preserve their initial offset.
    func createWithOrigin(rate: FrameRate, clockFrequency: u64, videoTimescale: u32, originTick: u64)->FramePacer fail
    {
        var result = try create(rate, clockFrequency, videoTimescale)
        result.firstTick    = originTick
        result.previousTick = originTick
        result.hasOrigin    = true
        return result
    }

    // Returns exact timing for any frame slot, including one skipped by capture.
    //
    // A caller can use this to timestamp a repeated picture for a missed slot. The returned
    // `skippedFrames` is zero because this query does not accept a captured picture.
    mtd const slotAt(index: u64)->FrameSlot fail
    {
        if index == Swag.U64.Max do
            fail OverflowError{"frame pacer frame position overflows"}
        let start = try .slotEnd(index)
        let end   = try .slotEnd(index + 1)
        if end - start > Swag.U32.Max do
            fail OverflowError{"frame pacer frame duration exceeds the packet range"}
        return FrameSlot{index, start, cast(u32, end - start), 0}
    }

    // Accepts a picture's monotonic timestamp if it enters a new frame slot.
    //
    // `tick` must not move backwards. On success `slot` receives exact video timing and the
    // number of skipped slots. A picture in the current slot returns false and leaves `slot`
    // untouched. Timestamp overflow fails before accepting the picture.
    mtd tryAccept(tick: u64, slot: *FrameSlot)->bool fail
    {
        if not .hasPicture and not .hasOrigin
        {
            slot[]        = try .slotAt(0)
            .firstTick    = tick
            .previousTick = tick
            .hasPicture   = true
            return true
        }

        if tick < .previousTick do
            fail BadParameterError{"frame pacer timestamps must not move backwards"}
        let elapsed      = tick - .firstTick
        let clockPeriod  = .clockFrequency * .rate.denominator()
        let wholePeriods = elapsed / clockPeriod
        if wholePeriods > Swag.U64.Max / .rate.numerator() do
            fail OverflowError{"frame pacer elapsed time exceeds its frame range"}
        let wholeFrames      = wholePeriods * .rate.numerator()
        let fractionalFrames = (elapsed % clockPeriod) * .rate.numerator() / clockPeriod
        if fractionalFrames > Swag.U64.Max - wholeFrames do
            fail OverflowError{"frame pacer elapsed time exceeds its frame range"}
        let current = wholeFrames + fractionalFrames
        if .hasPicture and current <= .previousSlot
        {
            .previousTick = tick
            return false
        }

        var accepted = try .slotAt(current)
        accepted.skippedFrames = .hasPicture ? current - .previousSlot - 1 : current
        slot[]        = accepted
        .previousTick = tick
        .previousSlot = current
        .hasPicture   = true
        return true
    }

    private mtd const slotEnd(index: u64)->u64 fail
    {
        if index > Swag.U64.Max / .rate.denominator() do
            fail OverflowError{"frame pacer frame position overflows"}
        let timebase = try Timebase.create(.videoTimescale)
        return try timebase.convertFrom(index * .rate.denominator(), .rate.numerator())
    }
}
