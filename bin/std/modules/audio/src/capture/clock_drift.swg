//! Format: capture-source clock drift estimator.
//! Supported: monotonic first-sample ticks and raw frame positions at 8-192 kHz.
//! Role: This file measures source-clock rate before a recorder places or resamples PCM.

#global public

using Core, Core.Errors

// Measures a capture device's rate against the recording's monotonic clock.
//
// Feed the *raw* cumulative frame position and timestamp of each captured block, before
// [[Audio.CaptureQueue]] reconciles gaps or overlaps. A window of source frames gives the
// difference from the nominal rate in parts per million. Apply that estimate to
// [[Audio.Resampler.setInputClockDriftPpm]] when its input rate matches this source. After a
// device restart, timestamp discontinuity, or dropped source frames, call `reset` with the
// first sound frame of the new continuous run. This estimator retains only four counters.
#[Swag.Opaque]
struct CaptureClockDrift
{
    internal
    {
        sampleRate:       u32
        clockFrequency:   u64
        windowTicks:      u64
        windowStartTick:  u64
        windowStartFrame: u64
        previousTick:     u64
        previousFrame:    u64
        ppm:              s32
        hasAnchor:        bool
        hasEstimate:      bool
    }
}

impl CaptureClockDrift
{
    // Creates a rate estimator with a one to 60 second observation window.
    //
    // The first estimate is available after one full window. A longer window reduces the
    // effect of timestamp rounding and callback jitter, but responds more slowly to changes.
    func create(sampleRate: u32, clockFrequency: u64, windowSeconds: u32 = 1)->CaptureClockDrift fail
    {
        if sampleRate < 8_000 or sampleRate > 192_000 or not clockFrequency or
           not windowSeconds or windowSeconds > 60 or
           clockFrequency > Swag.U64.Max / windowSeconds do
            fail BadParameterError{"capture drift needs an 8-192 kHz source and a representable 1-60 second window"}
        return CaptureClockDrift{sampleRate, clockFrequency, clockFrequency * windowSeconds}
    }

    // Clears the estimate and anchors a continuous source run at one sample timestamp.
    mtd reset(firstTick: u64, sourceFrame: u64)
    {
        .windowStartTick = firstTick
        .windowStartFrame = sourceFrame
        .previousTick = firstTick
        .previousFrame = sourceFrame
        .ppm = 0
        .hasAnchor = true
        .hasEstimate = false
    }

    // Observes the first sample of another continuous captured block.
    //
    // Returns true when a new one to 60 second estimate is ready. Each pair of positions must
    // increase strictly. A measured offset beyond 1000 ppm is treated as a discontinuity and
    // fails without changing state; reset after handling that source interruption. Calls before
    // a full window preserve the previous estimate.
    mtd observe(firstTick: u64, sourceFrame: u64)->bool fail
    {
        if not .hasAnchor
        {
            .reset(firstTick, sourceFrame)
            return false
        }
        if firstTick <= .previousTick or sourceFrame <= .previousFrame do
            fail BadParameterError{"capture drift needs increasing source ticks and frame positions"}
        let elapsed = firstTick - .windowStartTick
        var measured = .ppm
        let ready = elapsed >= .windowTicks
        if ready
        {
            let frames = sourceFrame - .windowStartFrame
            let rate = cast(f64, frames) * .clockFrequency / elapsed
            let offset = (rate / .sampleRate - 1.0) * 1_000_000.0
            if offset < -1_000.0 or offset > 1_000.0 do
                fail BadParameterError{"capture clock jump exceeds the supported drift range"}
            measured = cast(s32, Math.round(offset))
        }
        .previousTick = firstTick
        .previousFrame = sourceFrame
        if ready
        {
            .windowStartTick = firstTick
            .windowStartFrame = sourceFrame
            .ppm = measured
            .hasEstimate = true
        }
        return ready
    }

    // Returns whether at least one full observation window has completed.
    mtd const estimateIsReady()->bool => .hasEstimate

    // Returns the latest measured input-clock offset in parts per million.
    //
    // Zero is returned until an estimate is ready; use `estimateIsReady` to distinguish it
    // from a measured zero offset.
    mtd const inputClockDriftPpm()->s32 => .ppm

    // Applies a ready estimate to a resampler driven by this capture source.
    //
    // Returns false and leaves the resampler unchanged before the first complete observation
    // window. A resampler configured for another input rate is rejected.
    mtd const applyTo(resampler: *Resampler)->bool fail
    {
        if resampler.inputRate != .sampleRate do
            fail BadParameterError{"capture drift and resampler input rates differ"}
        if not .hasEstimate do
            return false
        try resampler.setInputClockDriftPpm(.ppm)
        return true
    }
}
