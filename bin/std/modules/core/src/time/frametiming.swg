#global public
#global namespace Time

// Tracks a clamped delta time for frame-based updates.
struct FrameTiming
{
    public
    {
        minimumDeltaSeconds: f32 = 1 / 100000.0     // Lower bound applied to each measured delta.
        maximumDeltaSeconds: f32 = 0.1              // Upper bound applied to each measured delta.

        public readonly
        {
            deltaSeconds: f32 = 1 / 60.0     // Delta time produced by the latest update.
            frameCount:   u64                // Number of unpaused updates.
            isPaused:     bool               // Whether updates are paused.
        }

        internal
        previousTick: u64
    }
}

impl FrameTiming
{
    // Updates the delta time and frame count
    mtd update()
    {
        let newTick = monotonicTicks()
        if .isPaused do
            return

        .frameCount += 1

        // First frame
        if !.previousTick
        {
            .previousTick = newTick
            return
        }

        // Delta time
        let diff = newTick - .previousTick
        .deltaSeconds = cast(f32) (cast(f64) diff / monotonicFrequency())
        .deltaSeconds = Math.clamp(.deltaSeconds, .minimumDeltaSeconds, .maximumDeltaSeconds)

        // Setup for next frame
        .previousTick = newTick
    }

    // Pauses frame timing and frame count
    mtd pause()
    {
        .isPaused = true
    }

    // Resumes frame timing and resets the tick reference.
    mtd resume()
    {
        if !.isPaused do
            return
        .isPaused     = false
        .previousTick = monotonicTicks()
    }
}
