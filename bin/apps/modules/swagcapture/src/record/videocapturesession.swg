using Core, Core.Errors, Pixel, Video

// Keeps one screen source, frame pacer and software MP4 writer alive for a recording.
//
// The caller drives `captureAt` with monotonic microsecond timestamps. Missed slots repeat the
// preceding frame; if the screen cannot be read, a black first frame or the last good frame
// fills the slot and the source is reopened. The session checks destination free space once
// per second and finalizes a playable prefix before the configured reserve is exhausted.
// Audio PCM16 can be added on zero through four separate tracks. The caller creates audio
// queues against `captureOriginTick` (microseconds)
// or `captureOrigin100ns` (WASAPI) after the first accepted picture, using the same monotonic
// clock to keep sound and video aligned.
#[Swag.NoCopy]
struct VideoCaptureSession
{
    source:        ScreenFrameSource
    recording:     Mp4.SoftwareRecording
    pacer:         FramePacer
    picture:       Image
    audioConfigs:  Array'Mp4.SoftwareAudioConfig
    outputDirectory: String
    originTick:    u64
    nextSpaceCheckTick: u64
    minimumFreeSpace:  u64
    hasOrigin:     bool
    lowStorageStop: bool
    sourceFailures: u64
}

impl VideoCaptureSession
{
    // Opens an MP4 recording of a physical desktop rectangle at the requested frame rate.
    //
    // `audioConfigs` may be empty for video-only capture; otherwise sound arrives later through
    // `addAudioFrames`. The area must have positive even pixel dimensions supported by H.264.
    // At least `minimumFreeSpace` bytes must remain on the destination volume at creation and
    // at periodic checks while recording; the default reserve is 64 MiB.
    func create(path: string, area: Math.Rectangle, rate: FrameRate, drawCursor: bool,
                audioConfigs: const [..] Mp4.SoftwareAudioConfig = [],
                minimumFreeSpace: u64 = 64 * 1_024 * 1_024)->VideoCaptureSession fail
    {
        let width = cast(s32, area.width)
        let height = cast(s32, area.height)
        let absolutePath = try Path.absolute(path)
        let outputDirectory = unwrap Path.directoryName(absolutePath.toString())
        if (try Directory.freeSpace(outputDirectory)) < minimumFreeSpace do
            fail Swag.SystemError{"video capture destination has insufficient free space"}
        var result: #returntype
        result.outputDirectory = outputDirectory
        result.minimumFreeSpace = minimumFreeSpace
        result.source = try ScreenFrameSource.create(drawCursor, cast(s32, area.x),
                                                      cast(s32, area.y), width, height)
        result.pacer = try FramePacer.create(rate, 1_000_000, 90_000)
        result.recording = try Mp4.SoftwareRecording.createWithAudioTracks(
            path, width, height, 90_000, audioConfigs)
        result.audioConfigs.add(audioConfigs)
        result.picture = Image.create(width, height, .BGRA8)
        Memory.set(result.picture.pixels.storage(), 0, result.picture.pixels.count)
        return result
    }

    // Captures at most one fresh picture at `tick`, filling every missed frame slot.
    //
    // Returns true only when a fresh screen image was accepted. A repeated or black frame is
    // still written when capture fails; a timestamp inside the current slot writes nothing.
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
                if .recording.videoFrameCount() do
                    try .recording.end()
                fail Swag.SystemError{"video capture stopped because the destination has little free space"}
            }
            .nextSpaceCheckTick = tick > Swag.U64.Max - 1_000_000 ? Swag.U64.Max : tick + 1_000_000
        }
        if not .hasOrigin
        {
            .originTick = tick
            .hasOrigin = true
        }
        for index in .recording.videoFrameCount() until slot.index
        {
            let missed = try .pacer.slotAt(index)
            if not .recording.videoFrameCount() do
                try .recording.addFrame(&.picture, missed)
            else do
                try .recording.repeatLastFrame(missed)
        }
        catch .source.grabInto(&.picture)
        {
            .sourceFailures += 1
            if not .recording.videoFrameCount() do
                try .recording.addFrame(&.picture, slot)
            else do
                try .recording.repeatLastFrame(slot)
            discard catch .source.reopen()
            return false
        }
        try .recording.addFrame(&.picture, slot)
        return true
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

    // Returns the number of written picture slots, including repeats.
    mtd const frameCount()->u64 => .recording.videoFrameCount()

    // Returns the number of slots filled from a previous picture after a missed grab.
    mtd const repeatedFrameCount()->u64 => .recording.repeatedFrameCount()

    // Returns the number of screen-source grabs that failed.
    mtd const sourceFailureCount()->u64 => .sourceFailures

    // Returns true when the session finalized its playable prefix before disk space ran out.
    mtd const stoppedForLowStorage()->bool => .lowStorageStop

    // Appends complete interleaved PCM16 frames to a selected sound track.
    mtd addAudioFrames(samples: const [..] s16, trackIndex: u32 = 0) fail
        => try .recording.addAudioFrames(samples, trackIndex)

    // Makes completed fragments durable without ending the capture.
    mtd flush() fail => try .recording.flush()

    // Completes every audio track and closes the fragmented MP4 file.
    mtd end() fail => try .recording.end()
}
