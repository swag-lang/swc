// The recording's monotonic timeline, shared by every track captured in one session. Video frames
// and audio samples can use elapsedAt with the same `now`, so pauses leave no gap between them.
struct RecordingClock
{
    resumedAt: u64     // Monotonic microseconds at the last start or resume.
    recorded:  u64     // Microseconds kept before the last resume.
    running:   bool
}

impl RecordingClock
{
    mtd startAt(now: u64)
    {
        .recorded  = 0
        .resumedAt = now
        .running   = true
    }

    mtd const elapsedAt(now: u64)->u64
    {
        if not .running do
            return .recorded
        return .recorded + (now - .resumedAt)
    }

    mtd pauseAt(now: u64)
    {
        if not .running do
            return
        .recorded = .elapsedAt(now)
        .running  = false
    }

    mtd resumeAt(now: u64)
    {
        if .running do
            return
        .resumedAt = now
        .running   = true
    }
}
