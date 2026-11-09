//! Format: source-clock-corrected capture packet adapter.
//! Supported: PCM16 or float source packets at 8-192 kHz into a 44.1/48 kHz queue.
//! Role: This file resamples a device clock to the recording clock without retaining a stream.

#global public

using Core, Core.Errors

// Converts native capture packets to a fixed recording rate with measured clock-drift correction.
//
// Give each packet its raw device frame position and monotonic first-sample timestamp. An
// [[Audio.CaptureClockDrift]] estimate adjusts [[Audio.Resampler]] as the source clock moves.
// Converted output is timestamped on the recording clock and copied into [[Audio.CaptureQueue]].
// On a discontinuity, the old filter tail is emitted, the filter phase restarts, and the queue
// records a loss/restoration boundary. A mono source is duplicated into stereo; a stereo source
// is averaged into mono. The adapter uses fixed-size input chunks and reuses its output arrays.
#[Swag.NoCopy]
struct CaptureResampledFeeder
{
    private
    {
        late queue:       *CaptureQueue
        feeder:           CapturePcmFeeder
        resampler:        Resampler
        clock:            CaptureClockDrift
        scratchInput:     [2 * 1_024] f32
        scratchOutput:    Array'f32
        channels:         u16
        sourceChannels:   u16
        inputRate:        u32
        outputRate:       u32
        clockFrequency:   u64
        firstTick:        u64
        emittedFrames:    u64
        hasRun:           bool
        finished:         bool
    }
}

impl CaptureResampledFeeder
{
    // Creates a bounded converter for a native source and a 44.1/48 kHz recording queue.
    //
    // `sourceChannels` defaults to the queue format for existing same-channel producers.
    func create(queue: *CaptureQueue, inputRate: u32,
                sourceChannels: u16 = 0)->CaptureResampledFeeder fail
    {
        let outputRate = queue.sampleRateHz()
        let nativeChannels = sourceChannels ? sourceChannels : queue.channelCount()
        if queue.channelCount() > 2 or not nativeChannels or nativeChannels > 2 or
           (outputRate != 44_100 and outputRate != 48_000) do
            fail BadParameterError{"resampled AAC capture needs mono/stereo 44.1 or 48 kHz output"}
        with var result: #returntype
        {
            .queue = queue
            .channels = queue.channelCount()
            .sourceChannels = nativeChannels
            .inputRate = inputRate
            .outputRate = outputRate
            .clockFrequency = queue.clockFrequencyHz()
            .feeder = CapturePcmFeeder.create(queue)
            .resampler = try Resampler.create(inputRate, outputRate, .channels)
            .clock = try CaptureClockDrift.create(inputRate, .clockFrequency)
        }
        return result
    }

    // Returns the latest input-device clock offset after one complete observation window.
    mtd const inputClockDriftPpm()->s32 => .clock.inputClockDriftPpm()

    // Returns whether the device clock has been measured for at least one full window.
    mtd const clockEstimateIsReady()->bool => .clock.estimateIsReady()

    // Adds one native PCM16 packet and its first raw frame position.
    mtd pushPcm16(samples: const [..] s16, firstTick: u64, sourceFrame: u64,
                  discontinuity: bool = false) fail
    {
        if .finished or not samples.count or samples.count % .sourceChannels do
            fail BadParameterError{"resampled capture needs complete nonempty PCM16 packets"}
        try .beginPacket(firstTick, sourceFrame, discontinuity)
        let frames = samples.count / .sourceChannels
        var offset = 0'u64
        while offset < frames
        {
            let count = Math.min(frames - offset, 1_024'u64)
            if .sourceChannels == .channels
            {
                for index in count * .channels do
                    .scratchInput[index] = cast(f32, samples[offset * .channels + index]) / 32_768.0
            }
            elif .sourceChannels == 1
            {
                for frame in count
                {
                    let value = cast(f32, samples[offset + frame]) / 32_768.0
                    .scratchInput[frame * 2] = value
                    .scratchInput[frame * 2 + 1] = value
                }
            }
            else
            {
                for frame in count
                {
                    let source = (offset + frame) * 2
                    .scratchInput[frame] = cast(f32, cast(s32, samples[source]) +
                                                      cast(s32, samples[source + 1])) / 65_536.0
                }
            }
            .scratchOutput.clear()
            try .resampler.addFrames(Swag.makeSlice(&.scratchInput[0], count * .channels), &.scratchOutput)
            try .emit()
            offset += count
        }
    }

    // Adds one native float32 packet and its first raw frame position.
    mtd pushFloat32(samples: const [..] f32, firstTick: u64, sourceFrame: u64,
                    discontinuity: bool = false) fail
    {
        if .finished or not samples.count or samples.count % .sourceChannels do
            fail BadParameterError{"resampled capture needs complete nonempty float packets"}
        try .beginPacket(firstTick, sourceFrame, discontinuity)
        let frames = samples.count / .sourceChannels
        var offset = 0'u64
        while offset < frames
        {
            let count = Math.min(frames - offset, 1_024'u64)
            .scratchOutput.clear()
            if .sourceChannels == .channels do
                try .resampler.addFrames(samples[offset * .channels until (offset + count) * .channels],
                                         &.scratchOutput)
            else
            {
                if .sourceChannels == 1
                {
                    for frame in count
                    {
                        let value = samples[offset + frame]
                        .scratchInput[frame * 2] = value
                        .scratchInput[frame * 2 + 1] = value
                    }
                }
                else
                {
                    for frame in count do
                        .scratchInput[frame] = 0.5 *
                            (samples[(offset + frame) * 2] + samples[(offset + frame) * 2 + 1])
                }
                try .resampler.addFrames(Swag.makeSlice(&.scratchInput[0], count * .channels),
                                         &.scratchOutput)
            }
            try .emit()
            offset += count
        }
    }

    // Adds one all-zero source packet without allocating a packet-sized buffer.
    mtd pushSilence(frames: u64, firstTick: u64, sourceFrame: u64,
                    discontinuity: bool = false) fail
    {
        if .finished or not frames do
            fail BadParameterError{"resampled capture needs nonempty silence packets"}
        try .beginPacket(firstTick, sourceFrame, discontinuity)
        var offset = 0'u64
        while offset < frames
        {
            let count = Math.min(frames - offset, 1_024'u64)
            for index in count * .channels do
                .scratchInput[index] = 0
            .scratchOutput.clear()
            try .resampler.addFrames(Swag.makeSlice(&.scratchInput[0], count * .channels), &.scratchOutput)
            try .emit()
            offset += count
        }
    }

    // Emits the final filter tail after the native source has stopped.
    //
    // Repeated calls do nothing. Call before finalizing the queue's AAC track so the final
    // captured samples remain audible through the resampler's 48-frame right context.
    mtd finish() fail
    {
        if .finished do
            return
        if .hasRun
        {
            .scratchOutput.clear()
            try .resampler.end(&.scratchOutput)
            try .emit()
        }
        .finished = true
    }

    // Drains the filter before a live source goes idle without marking a device failure.
    //
    // Output loopback can stop sending packets when the render mix becomes silent. This emits
    // its last 48 delayed input frames before the caller commits silence on the queue. A new
    // source packet starts a fresh filter run at its own monotonic timestamp.
    mtd suspendForIdle() fail
    {
        if not .hasRun or .finished do
            return
        .scratchOutput.clear()
        try .resampler.end(&.scratchOutput)
        try .emit()
        .resampler.restart()
        .hasRun = false
    }
}

private impl CaptureResampledFeeder
{
    mtd beginPacket(firstTick: u64, sourceFrame: u64, discontinuity: bool) fail
    {
        if not .hasRun
        {
            .startRun(firstTick, sourceFrame)
            return
        }
        if discontinuity or .queue.sourceIsLost()
        {
            try .restartRun(firstTick, sourceFrame)
            return
        }
        var clockError: Swag.Error
        discard catch .clock.observe(firstTick, sourceFrame) as clockError
        if clockError.value() != null
        {
            try .restartRun(firstTick, sourceFrame)
            return
        }
        discard try .clock.applyTo(&.resampler)
    }

    mtd startRun(firstTick: u64, sourceFrame: u64)
    {
        .firstTick = firstTick
        .emittedFrames = 0
        .clock.reset(firstTick, sourceFrame)
        .hasRun = true
    }

    mtd restartRun(firstTick: u64, sourceFrame: u64) fail
    {
        if not .queue.sourceIsLost()
        {
            .scratchOutput.clear()
            try .resampler.end(&.scratchOutput)
            try .emit()
            try .queue.markLost(firstTick)
        }
        try .queue.markRestored(firstTick)
        .resampler.restart()
        .startRun(firstTick, sourceFrame)
    }

    mtd emit() fail
    {
        let frames = .scratchOutput.count / .channels
        if not frames do
            return
        if frames > Swag.U64.Max - .emittedFrames do
            fail OverflowError{"resampled capture output frame count overflows"}
        let whole = .emittedFrames / .outputRate
        let remainder = .emittedFrames % .outputRate
        if whole > (Swag.U64.Max - .firstTick) / .clockFrequency do
            fail OverflowError{"resampled capture output timestamp overflows"}
        let base = .firstTick + whole * .clockFrequency
        let scaled = remainder * .clockFrequency
        let fraction = scaled / .outputRate +
                       cast(u64, scaled % .outputRate >= .outputRate / 2 + .outputRate % 2)
        if fraction > Swag.U64.Max - base do
            fail OverflowError{"resampled capture output timestamp overflows"}
        try .feeder.pushFloat32(.scratchOutput.toSlice(), base + fraction)
        .emittedFrames += frames
    }
}
