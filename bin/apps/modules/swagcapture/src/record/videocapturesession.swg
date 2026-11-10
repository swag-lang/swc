using Core, Core.Errors, Pixel, Video

// Keeps one screen source, frame pacer and software MP4 writer alive for a recording.
//
// The caller drives `captureAt` with monotonic microsecond timestamps. Short missed intervals
// repeat each frame slot; long gaps use a held picture with a long duration, so a suspended
// recorder does not encode hours of identical frames. If the screen cannot be read, a black
// first frame or the last good frame fills the slot and the source is reopened. The session
// checks destination free space once per second and stops before the configured reserve is
// exhausted. Stop audio producers, then call `end` to finalize the playable prefix.
// Audio PCM16 can be added on zero through four separate tracks. The caller creates audio
// queues against `captureOriginTick` (microseconds)
// or `captureOrigin100ns` (WASAPI) after the first accepted picture, using the same monotonic
// clock to keep sound and video aligned.
// `startEncoder` enables a bounded asynchronous handoff before the first picture. Counters then
// describe submitted slots; `flush` waits for their encoding and `end` joins the worker.
#[Swag.NoCopy]
struct VideoCaptureSession
{
    source:                   ScreenFrameSource
    recording:                Mp4.SoftwareRecording
    pacer:                    FramePacer
    picture:                  Image
    audioConfigs:             Array'Mp4.SoftwareAudioConfig
    outputDirectory:          String
    originTick:               u64
    nextVideoTime:            u64
    missedSlots:              u64
    nextSpaceCheckTick:       u64
    minimumFreeSpace:         u64
    hasOrigin:                bool
    lowStorageStop:           bool
    sourceFailures:           u64
    grabMicroseconds:         u64
    producerWaitMicroseconds: u64
    freshFrames:              u64
    submittedFrames:          u64
    submittedRepeats:         u64
    encoder:                  VideoCaptureEncoder
}

impl VideoCaptureSession
{
    // Opens an MP4 recording of a physical desktop rectangle at the requested frame rate.
    //
    // `audioConfigs` may be empty for video-only capture; otherwise sound arrives later through
    // `addAudioFrames`. The area must have positive even pixel dimensions supported by H.264.
    // At least `minimumFreeSpace` bytes must remain on the destination volume at creation and
    // at periodic checks while recording; the default reserve is 64 MiB.
    // `quantizationQp` is 0 for exact pictures or 1 through 51 for quantized pictures.
    // It does not select a target bitrate.
    // `sliceCount` divides a picture into 1 to 8 independently coded row bands.
    func create(path: string, area: Math.Rectangle, rate: FrameRate, drawCursor: bool, audioConfigs: const [..] Mp4.SoftwareAudioConfig = [], minimumFreeSpace: u64 = 64 * 1_024 * 1_024, quantizationQp: u32 = 0, sliceCount: u32 = 1)->VideoCaptureSession fail
    {
        let width           = cast(s32, area.width)
        let height          = cast(s32, area.height)
        let absolutePath    = try Path.absolute(path)
        let outputDirectory = unwrap Path.directoryName(absolutePath.toString())
        if (try Directory.freeSpace(outputDirectory)) < minimumFreeSpace do
            fail Swag.SystemError{"video capture destination has insufficient free space"}
        var result: #returntype
        result.outputDirectory  = outputDirectory
        result.minimumFreeSpace = minimumFreeSpace
        result.source           = try ScreenFrameSource.create(drawCursor, cast(s32, area.x), cast(s32, area.y), width, height)
        result.pacer            = try FramePacer.create(rate, 1_000_000, 90_000)
        result.recording        = try Mp4.SoftwareRecording.createWithAudioTracks(path, width, height, 90_000, audioConfigs, quantizationQp: quantizationQp, sliceCount: sliceCount)
        result.audioConfigs.add(audioConfigs)
        result.picture = Image.create(width, height, .BGRA8)
        Memory.set(result.picture.pixels.storage(), 0, result.picture.pixels.count)
        return result
    }

    // Captures at most one fresh picture at `tick`, filling every missed frame slot.
    //
    // Returns true only when a fresh screen image was accepted. A repeated or black frame is
    // still written when capture fails; a timestamp inside the current slot writes nothing.
    // Up to 120 missed slots remain individual frames; longer intervals become held samples.
    mtd captureAt(tick: u64)->bool fail
    {
        if .lowStorageStop do
            fail Swag.SystemError{"video capture stopped because the destination has little free space"}
        var slot: FrameSlot
        if not try .pacer.tryAccept(tick, &slot) do
            return false
        if tick >= .nextSpaceCheckTick
        {
            if (try Directory.freeSpace(.outputDirectory.toString())) < .minimumFreeSpace
            {
                .lowStorageStop = true
                fail Swag.SystemError{"video capture stopped because the destination has little free space"}
            }

            .nextSpaceCheckTick = tick > Swag.U64.Max - 1_000_000 ? Swag.U64.Max : tick + 1_000_000
        }

        if not .hasOrigin
        {
            .originTick = tick
            .hasOrigin  = true
        }

        if slot.decodeTime < .nextVideoTime do
            fail BadParameterError{"video capture pacer moved behind the encoded timeline"}
        if slot.skippedFrames > Swag.U64.Max - .missedSlots do
            fail OverflowError{"video capture missed-slot counter overflows"}
        .missedSlots += slot.skippedFrames
        if slot.skippedFrames <= 120
        {
            for index in slot.index - slot.skippedFrames until slot.index
            {
                let missed = try .pacer.slotAt(index)
                try .writeRepeatedPicture(missed.duration)
            }
        }
        else
        {
            // One long sample represents a stable screen across a large interruption. MP4
            // sample duration is u32, so very long gaps are split into bounded chunks.
            while .nextVideoTime < slot.decodeTime
            {
                let duration = cast(u32,
                                    Math.min(slot.decodeTime - .nextVideoTime,
                                             cast(u64, Swag.U32.Max)))
                try .writeRepeatedPicture(duration)
            }
        }

        if slot.decodeTime != .nextVideoTime do
            fail BadParameterError{"video capture gap did not align with the next frame"}
        let outputSlot = FrameSlot{.submittedFrames, .nextVideoTime,
                                   slot.duration, 0}
        let grabStart = Time.monotonicMicroseconds()
        catch .source.grabInto(&.picture)
        {
            .sourceFailures += 1
            try .writeFrame(outputSlot, .submittedFrames != 0)
            .nextVideoTime += slot.duration
            discard catch .source.reopen()
            return false
        }

        .grabMicroseconds += Time.monotonicMicroseconds() - grabStart
        let encodeStart = Time.monotonicMicroseconds()
        try .writeFrame(outputSlot, false)
        .producerWaitMicroseconds += Time.monotonicMicroseconds() - encodeStart
        .freshFrames   += 1
        .nextVideoTime += slot.duration
        return true
    }

    private mtd writeRepeatedPicture(duration: u32) fail
    {
        let repeated = FrameSlot{.submittedFrames, .nextVideoTime, duration, 0}
        try .writeFrame(repeated, .submittedFrames != 0)
        .nextVideoTime += duration
    }

    // Returns whether the first video slot established a monotonic origin.
    mtd const hasCaptureOrigin()->bool => .hasOrigin

    // Returns the first accepted capture tick for audio queues using a microsecond clock.
    mtd const captureOriginTick()->u64 => .originTick

    // Returns the same origin in 100-nanosecond units for Windows WASAPI capture queues.
    //
    // Windows `Time.monotonicMicroseconds` and WASAPI timestamps use the same performance
    // counter. Call this after `hasCaptureOrigin`; conversion loses at most one microsecond.
    mtd const captureOrigin100ns()->u64 fail
    {
        if not .hasOrigin do
            fail BadParameterError{"video capture has no first frame origin yet"}
        if .originTick > Swag.U64.Max / 10 do
            fail OverflowError{"video capture origin exceeds the WASAPI timestamp range"}
        return .originTick * 10
    }

    // Returns accepted picture slots, including repeats; an asynchronous encoder may lag.
    mtd const frameCount()->u64 => .submittedFrames

    // Returns the number of slots filled from a previous picture after a missed grab.
    mtd const repeatedFrameCount()->u64 => .submittedRepeats

    // Returns real-time frame slots missed by screen acquisition, including condensed gaps.
    mtd const missedFrameSlotCount()->u64 => .missedSlots

    // Returns the number of screen-source grabs that failed.
    mtd const sourceFailureCount()->u64 => .sourceFailures

    // Returns true when the session stopped for storage; stop audio producers before `end`.
    mtd const stoppedForLowStorage()->bool => .lowStorageStop

    // Appends complete interleaved PCM16 frames to a selected sound track.
    mtd addAudioFrames(samples: const [..] s16, trackIndex: u32 = 0) fail
        => try .recording.addAudioFrames(samples, trackIndex)

    // Makes completed fragments durable without ending the capture.
    mtd flush() fail
    {
        try .encoder.waitIdle()
        try .recording.flush()
    }

    // Completes every audio track and closes the fragmented MP4 file.
    mtd end() fail
    {
        try .encoder.finish()
        try .recording.end()
    }

    mtd startEncoder() fail
    {
        if .submittedFrames or .encoder.enabled do
            fail BadParameterError{"start the video capture encoder before submitting pictures"}
        try .encoder.start(&.recording)
    }

    private mtd writeFrame(slot: FrameSlot, repeated: bool) fail
    {
        if .encoder.enabled do
            try .encoder.add(&.picture, slot, repeated)
        elif repeated do
            try .recording.repeatLastFrame(slot)
        else do
            try .recording.addFrame(&.picture, slot)
        .submittedFrames += 1
        if repeated do
            .submittedRepeats += 1
    }

    mtd opDrop() => .encoder.close()
}
