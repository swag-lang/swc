//! Format: capture-device loss and retry policy.
//! Supported: fixed retry intervals on a caller-supplied monotonic clock.
//! Role: This file keeps a recording timeline alive while its input device is unavailable.
//
#global public

using Core, Core.Errors

// Coordinates capture-device loss and reopen attempts with a timestamped PCM queue.
//
// The platform worker calls `deviceLost` when an input fails, checks `retryDue`, then calls
// `retryFailed` or `deviceRestored` after its attempt. Every failed retry advances the queue's
// silent gap. The controller retains no audio and makes no platform call. Keep the referenced
// [[Audio.CaptureQueue]] alive and use this controller for all of its device-state changes.
#[Swag.NoCopy]
struct CaptureRecovery
{
    private
    {
        late queue: *CaptureQueue
        retryDelay: u64
        nextRetry: u64
        lost:       bool
    }
}

impl CaptureRecovery
{
    // Creates a retry controller with a strictly positive interval in queue-clock ticks.
    func create(queue: *CaptureQueue, retryDelayTicks: u64)->CaptureRecovery fail
    {
        if not retryDelayTicks or queue.sourceIsLost() do
            fail BadParameterError{"capture recovery needs a live queue and a positive retry interval"}
        with var result: #returntype
        {
            .queue = queue
            .retryDelay = retryDelayTicks
        }
        return result
    }

    // Reports whether an input device is currently unavailable.
    mtd const isLost()->bool => .lost

    // Returns the earliest monotonic tick for the next reopen attempt.
    mtd const nextRetryTick()->u64 => .nextRetry

    // Marks an input failure and schedules its first reopen attempt.
    //
    // Repeated loss notifications extend the queue's gap without delaying an already due retry.
    mtd deviceLost(tick: u64) fail
    {
        if not .lost and tick > Swag.U64.Max - .retryDelay do
            fail OverflowError{"capture retry deadline overflows"}
        try .queue.markLost(tick)
        if not .lost
        {
            .nextRetry = tick + .retryDelay
            .lost = true
        }
    }

    // Reports whether a reopen should be attempted now.
    mtd const retryDue(tick: u64)->bool => .lost and tick >= .nextRetry

    // Records a failed reopen attempt and schedules the next one.
    //
    // Calls before the deadline or after recovery are rejected without changing the queue.
    mtd retryFailed(tick: u64) fail
    {
        if not .retryDue(tick) do
            fail BadParameterError{"capture retry is not due"}
        if tick > Swag.U64.Max - .retryDelay do
            fail OverflowError{"capture retry deadline overflows"}
        try .queue.markLost(tick)
        .nextRetry = tick + .retryDelay
    }

    // Marks a reopened device ready and preserves the full outage as a sample gap.
    mtd deviceRestored(tick: u64) fail
    {
        if not .lost do
            return
        try .queue.markRestored(tick)
        .lost = false
        .nextRetry = 0
    }
}
