using Core, Core.Errors, Audio

// Transfers one timestamped capture queue to its own MP4 sound track in bounded chunks.
//
// The queue can be written by a WASAPI producer on another thread. Lost blocks, device outages
// and idle output loopback intervals become encoded silence. `pump` emits at most `maxFrames`
// per call, so even a multi-hour source gap cannot stall the interface in one invocation.
// Keep the session and queue alive until their final `pump` and `end` calls have completed.
// This pump is the sole PCM writer for its selected track.
#[Swag.NoCopy]
struct VideoAudioPump
{
    late session:       *VideoCaptureSession
    late queue:         *CaptureQueue
    samples:            Array's16
    block:              CaptureBlock
    offset:             u64
    nextSample:         u64
    syntheticFrames:    u64
    interruptionCount:  u64
    trackIndex:         u32
    channels:           u16
    hasBlock:           bool
    zeros:              [2 * 1_024] s16
}

impl VideoAudioPump
{
    // Binds one PCM queue to an empty AAC track with the same sample rate and channels.
    func create(session: *VideoCaptureSession, queue: *CaptureQueue,
                trackIndex: u32)->VideoAudioPump fail
    {
        if trackIndex >= session.audioConfigs.count do
            fail BadParameterError{"video session has no audio track at this index"}
        let config = session.audioConfigs[trackIndex]
        if queue.sampleRateHz() != config.sampleRate or
           queue.channelCount() != config.channelCount or
           (try session.recording.audioInputFrameCountOf(trackIndex)) != 0 do
            fail BadParameterError{"capture queue does not match an empty MP4 sound track"}
        var result: #returntype
        result.session = session
        result.queue = queue
        result.trackIndex = trackIndex
        result.channels = config.channelCount
        return result
    }

    // Returns PCM frames already forwarded to the MP4 sound track, including inserted silence.
    mtd const inputFrameCount()->u64 => .nextSample

    // Returns frames synthesized to span source gaps or inactive output loopback.
    mtd const syntheticFrameCount()->u64 => .syntheticFrames

    // Returns captured blocks that reported a source restoration.
    mtd const sourceInterruptionCount()->u64 => .interruptionCount

    // Pumps at most `maxFrames` of queued or missing sound into the recording.
    //
    // Repeated calls resume a partially consumed queue block without losing its samples. Zero
    // means no sound is available yet. The per-call bound is 1 through 65536 sample frames.
    mtd pump(maxFrames: u32 = 4_096)->u64 fail
    {
        if not maxFrames or maxFrames > 65_536 do
            fail BadParameterError{"capture audio pump frame budget is outside 1-65536"}
        if (try .session.recording.audioInputFrameCountOf(.trackIndex)) != .nextSample do
            fail BadParameterError{"capture audio track also received PCM outside its pump"}
        var emitted = 0'u64
        while emitted < maxFrames
        {
            if .hasBlock
            {
                if .nextSample < .block.startSample
                {
                    let count = Math.min(cast(u64, maxFrames) - emitted,
                                         .block.startSample - .nextSample)
                    let inserted = try .addSilence(count)
                    emitted += inserted
                    continue
                }
                .offset = Math.max(.offset, .nextSample - .block.startSample)
                if .offset >= cast(u64, .block.frameCount)
                {
                    .hasBlock = false
                    continue
                }
                let count = Math.min(cast(u64, maxFrames) - emitted,
                                     cast(u64, .block.frameCount) - .offset)
                let begin = .offset * .channels
                try .session.addAudioFrames(.samples.toSlice()[begin until begin + count * .channels],
                                            .trackIndex)
                .offset += count
                .nextSample += count
                emitted += count
                if .offset == cast(u64, .block.frameCount) do
                    .hasBlock = false
                continue
            }

            if .queue.pop(&.samples, &.block)
            {
                .hasBlock = true
                .offset = 0
                if .block.sourceInterrupted do
                    .interruptionCount += 1
                continue
            }
            let silentEnd = .queue.silentGapEnd()
            if silentEnd <= .nextSample do
                break
            let count = Math.min(cast(u64, maxFrames) - emitted,
                                 silentEnd - .nextSample)
            emitted += try .addSilence(count)
        }
        return emitted
    }

    private mtd addSilence(frameCount: u64)->u64 fail
    {
        var remaining = frameCount
        while remaining
        {
            let count = Math.min(remaining, 1_024'u64)
            try .session.addAudioFrames(Swag.makeSlice(&.zeros[0], count * .channels), .trackIndex)
            .nextSample += count
            .syntheticFrames += count
            remaining -= count
        }
        return frameCount
    }
}
