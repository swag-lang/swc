//! Format: native capture packet to timestamped PCM16 queue adapter.
//! Supported: interleaved PCM16, float32, silence, discontinuity, and bounded packet splitting.
//! Role: This file keeps OS packet conversion separate from device ownership.

#global public

using Core, Core.Errors

// Copies a native capture packet into [[Audio.CaptureQueue]] in bounded PCM16 blocks.
//
// The input timestamps and the queue use the same monotonic tick frequency. Float samples outside
// [-1, 1] are clipped; non-finite samples become zero. A device discontinuity creates a reported
// loss/restoration boundary before the next block. Each native packet is split at the queue's
// configured maximum block size. Timestamp overflow is rejected before the queue state changes.
// Keep the queue alive while using this adapter.
#[Swag.NoCopy]
struct CapturePcmFeeder
{
    private
    {
        late queue:  *CaptureQueue
        scratch:     Array's16
        channels:    u16
        sampleRate:  u32
        maximum:     u32
        clockRate:   u64
    }
}

impl CapturePcmFeeder
{
    // Creates an adapter for a timestamped capture queue.
    func create(queue: *CaptureQueue)->CapturePcmFeeder
    {
        with var result: #returntype
        {
            .queue = queue
            .channels = queue.channelCount()
            .sampleRate = queue.sampleRateHz()
            .maximum = queue.maximumBlockFrames()
            .clockRate = queue.clockFrequencyHz()
            .scratch.resize(cast(u64, .maximum) * .channels)
        }
        return result
    }

    // Submits one interleaved signed 16-bit source packet.
    mtd pushPcm16(samples: const [..] s16, firstTick: u64, discontinuity: bool = false) fail
    {
        if not samples.count or samples.count % .channels do
            fail BadParameterError{"capture PCM16 packet needs complete nonempty frames"}
        let frames = samples.count / .channels
        try .preflightTicks(firstTick, frames)
        try .beginPacket(firstTick, discontinuity)
        var offset = 0'u64
        while offset < frames
        {
            let count = Math.min(frames - offset, .maximum)
            let tick = try .tickAt(firstTick, offset)
            discard try .queue.push(samples[offset * .channels until (offset + count) * .channels], tick)
            offset += count
        }
    }

    // Submits one interleaved 32-bit floating-point source packet.
    mtd pushFloat32(samples: const [..] f32, firstTick: u64, discontinuity: bool = false) fail
    {
        if not samples.count or samples.count % .channels do
            fail BadParameterError{"capture float packet needs complete nonempty frames"}
        let frames = samples.count / .channels
        try .preflightTicks(firstTick, frames)
        try .beginPacket(firstTick, discontinuity)
        var offset = 0'u64
        while offset < frames
        {
            let count = Math.min(frames - offset, .maximum)
            for index in count * .channels
            {
                let sample = samples[offset * .channels + index]
                .scratch[index] = Math.isFinite(sample) ?
                                  cast(s16, Math.clamp(Math.round(cast(f64, sample) * 32_768.0),
                                                       -32_768.0, 32_767.0)) : 0
            }
            let tick = try .tickAt(firstTick, offset)
            discard try .queue.push(.scratch.toSlice()[0 until count * .channels], tick)
            offset += count
        }
    }

    // Submits a silent native packet without allocating a packet-sized PCM buffer.
    mtd pushSilence(frames: u64, firstTick: u64, discontinuity: bool = false) fail
    {
        if not frames do
            fail BadParameterError{"capture silence packet needs frames"}
        try .preflightTicks(firstTick, frames)
        try .beginPacket(firstTick, discontinuity)
        var offset = 0'u64
        while offset < frames
        {
            let count = Math.min(frames - offset, .maximum)
            for index in count * .channels do
                .scratch[index] = 0
            let tick = try .tickAt(firstTick, offset)
            discard try .queue.push(.scratch.toSlice()[0 until count * .channels], tick)
            offset += count
        }
    }
}

private impl CapturePcmFeeder
{
    mtd preflightTicks(firstTick: u64, frames: u64) fail
    {
        let lastOffset = ((frames - 1) / .maximum) * .maximum
        discard try .tickAt(firstTick, lastOffset)
    }

    mtd beginPacket(firstTick: u64, discontinuity: bool) fail
    {
        if discontinuity do
            try .queue.markLost(firstTick)
        if .queue.sourceIsLost() do
            try .queue.markRestored(firstTick)
    }

    mtd tickAt(firstTick: u64, offset: u64)->u64 fail
    {
        let whole = offset / .sampleRate
        let remainder = offset % .sampleRate
        if whole > (Swag.U64.Max - firstTick) / .clockRate do
            fail OverflowError{"capture packet timestamp overflows"}
        let base = firstTick + whole * .clockRate
        let scaled = remainder * .clockRate
        let fraction = scaled / .sampleRate +
                       cast(u64, scaled % .sampleRate >= .sampleRate / 2 + .sampleRate % 2)
        if fraction > Swag.U64.Max - base do
            fail OverflowError{"capture packet timestamp overflows"}
        return base + fraction
    }
}
