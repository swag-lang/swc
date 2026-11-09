//! Format: software H.264 and AAC-LC recording into fragmented MP4.
//! Supported: sequential constant-rate frame slots and arbitrarily chunked mono/stereo PCM16.
//! Role: This file connects the portable encoders to a recoverable audiovisual container.
//
#global namespace Mp4
#global export

using Core, Core.Errors, Pixel, Audio

// Configures one separately retained AAC-LC sound track in a software recording.
struct SoftwareAudioConfig
{
    public sampleRate:   u32           // Input PCM16 frames per second; all tracks share one rate.
    public channelCount: u16           // One or two interleaved input channels.
    public bandwidth:    Aac.Bandwidth = .Full // Full or voice-band encoding.
}

private struct SoftwareAudioTrack
{
    encoder: Aac.StreamEncoder
    packet:  Array'u8
}

// Records RGB pictures and PCM16 sound as a fragmented MP4 without codec libraries.
//
// The caller assigns video slots with [[Video.FramePacer]]. Every slot, including a repeated
// picture for a missed capture, must be submitted in order. Sound may arrive in arbitrary
// complete-frame chunks. With audio, the first video packet begins one AAC priming packet after
// sound. The live prefix lets [[Video.Reader]] derive the 1024-sample encoder delay; `end`
// publishes standard edit lists that align both tracks at zero and omit final AAC padding.
// It drains audio before finalizing the file. Internal
// picture, PCM and packet storage stays bounded as the recording grows. Up to four independent
// sound tracks share one sample rate; a capture source can be kept on each track for later mixing.
// A video-only recording starts at video time zero and needs no audio device.
// Video quantization parameter 0 preserves exact samples. Values 1 through 51 may quantize
// textured IDR and P pictures; this fixed setting does not target a bitrate.
// Each picture may use one through eight H.264 slices, up to its macroblock-row count.
#[Swag.NoCopy]
#[Swag.Opaque]
struct SoftwareRecording
{
    private
    {
        writer:        FragmentedWriter
        video:         H264.Encoder
        tracks:        Array'SoftwareAudioTrack
        nv12:          Nv12Frame
        videoOffset:   u64
        nextVideoTime: u64
        frameCount:    u64
        repeatedFrames: u64
        ended:         bool
    }
}

impl SoftwareRecording
{
    // Creates a video-only recorder when no sound source is selected or available.
    //
    // Video dimensions must be positive and even, and the timescale must express each frame
    // duration. The resulting MP4 has one video track and no empty sound track.
    // `quantizationQp` defaults to exact mode at 0, accepts values through 51, and can make
    // textured IDR and P pictures lossy. `sliceCount` defaults to one and accepts up to eight
    // complete macroblock-row bands.
    func createVideoOnly(path: string, width, height: s32, videoTimescale: u32,
                         keyInterval: u32 = 60,
                         options: FragmentedOptions = {},
                         quantizationQp: u32 = 0,
                         sliceCount: u32 = 1)->SoftwareRecording fail
        => try createWithAudioTracks(path, width, height, videoTimescale, [], keyInterval,
                                     options, quantizationQp, sliceCount)

    // Creates a software audiovisual recorder and writes the MP4 initialization movie.
    //
    // Video dimensions must be positive and even. The video timescale must express each
    // intended frame duration and distinguish AAC's 1024-frame priming boundary. AAC accepts
    // mono/stereo 44.1 or 48 kHz PCM16. The writer owns
    // the output path; completed fragments stay playable after an interrupted process.
    // `quantizationQp` defaults to exact mode at 0, accepts values through 51, and can make
    // textured IDR and P pictures lossy. `sliceCount` defaults to one and accepts up to eight
    // complete macroblock-row bands.
    func create(path: string, width, height: s32, videoTimescale: u32,
                audioRate: u32, audioChannels: u16, keyInterval: u32 = 60,
                bandwidth: Aac.Bandwidth = .Full,
                options: FragmentedOptions = {},
                quantizationQp: u32 = 0,
                sliceCount: u32 = 1)->SoftwareRecording fail
    {
        let configs: [1] SoftwareAudioConfig = [{audioRate, audioChannels, bandwidth}]
        return try createWithAudioTracks(path, width, height, videoTimescale,
                                         Swag.makeSlice(&configs[0], configs.count),
                                         keyInterval, options, quantizationQp, sliceCount)
    }

    // Creates a recorder with zero through four separately encoded AAC-LC sound tracks.
    //
    // Every track must have the same 44.1 or 48 kHz sample rate so one video preroll aligns
    // their AAC priming. Their channel counts and bandwidth profiles may differ. The writer
    // copies decoder configurations and owns the output path.
    // `quantizationQp` defaults to exact mode at 0, accepts values through 51, and can make
    // textured IDR and P pictures lossy. `sliceCount` defaults to one and accepts up to eight
    // complete macroblock-row bands.
    func createWithAudioTracks(path: string, width, height: s32, videoTimescale: u32,
                               audioConfigs: const [..] SoftwareAudioConfig,
                               keyInterval: u32 = 60,
                               options: FragmentedOptions = {},
                               quantizationQp: u32 = 0,
                               sliceCount: u32 = 1)->SoftwareRecording fail
    {
        if audioConfigs.count > 4 do
            fail BadParameterError{"software recording supports at most four audio tracks"}
        var result: #returntype
        result.video = try H264.Encoder.create(width, height, keyInterval,
                                               quantizationQp, sliceCount)
        if not audioConfigs.count
        {
            result.writer = try FragmentedWriter.create(path, width, height, videoTimescale,
                                                        result.video.decoderConfig(), options)
            return result
        }
        result.tracks.reserve(audioConfigs.count)
        for config in audioConfigs
        {
            if config.sampleRate != audioConfigs[0].sampleRate do
                fail BadParameterError{"software recording audio tracks need one sample rate"}
            var track: SoftwareAudioTrack
            track.encoder = try Aac.StreamEncoder.create(config.sampleRate, config.channelCount,
                                                         config.bandwidth)
            result.tracks.add(#move track)
        }
        let clock = try Timebase.create(videoTimescale)
        let delay = result.tracks[0].encoder.encoderDelayFrames()
        // A rounded offset can move video past the priming boundary: at 44.1 kHz and a
        // 90 kHz video clock, 2090 ticks would make Reader remove 1025 samples. Choose the
        // preceding tick and ensure it still maps to exactly `delay` trimmed samples.
        result.videoOffset = cast(u64, delay) * clock.ticksPerSecond() /
                             audioConfigs[0].sampleRate
        if delay and result.videoOffset * audioConfigs[0].sampleRate <=
                     cast(u64, delay - 1) * clock.ticksPerSecond() do
            fail BadParameterError{"video timescale cannot express AAC priming to one sample"}
        var mp4Configs: Array'FragmentedAudioConfig
        for index in audioConfigs.count
        {
            let config = audioConfigs[index]
            mp4Configs.add({config.sampleRate, config.channelCount,
                            result.tracks[index].encoder.decoderConfig()})
        }
        result.writer = try FragmentedWriter.createWithAudioTracks(path, width, height,
                                                                   videoTimescale,
                                                                   result.video.decoderConfig(),
                                                                   mp4Configs.toSlice(), options)
        return result
    }

    // Returns the AAC priming offset in video ticks, or zero for video-only recording.
    mtd const videoPrerollTicks()->u64 => .videoOffset

    // Returns the number of accepted video frames, including caller-supplied repeats.
    mtd const videoFrameCount()->u64 => .frameCount

    // Returns the number of frame slots filled by repeating the previous picture.
    mtd const repeatedFrameCount()->u64 => .repeatedFrames

    // Returns the number of independent AAC-LC sound tracks.
    mtd const audioTrackCount()->u64 => .tracks.count

    // Returns source PCM16 frames consumed by the first track, or zero without audio.
    mtd const audioInputFrameCount()->u64 => .tracks.count ?
        .tracks[0].encoder.inputFrameCount() : 0

    // Returns AAC-LC packets on the first track, or zero without audio.
    mtd const audioPacketCount()->u64 => .tracks.count ?
        .tracks[0].encoder.packetCount() : 0

    // Returns source PCM16 frames consumed by the selected sound track.
    mtd const audioInputFrameCountOf(trackIndex: u32)->u64 fail
    {
        if trackIndex >= .tracks.count do
            fail BadParameterError{"software recording has no audio track at this index"}
        return .tracks[trackIndex].encoder.inputFrameCount()
    }

    // Returns AAC-LC packets submitted on the selected track, including its drain packet.
    mtd const audioPacketCountOf(trackIndex: u32)->u64 fail
    {
        if trackIndex >= .tracks.count do
            fail BadParameterError{"software recording has no audio track at this index"}
        return .tracks[trackIndex].encoder.packetCount()
    }

    // Returns bytes written through completed MP4 fragments and the initialization movie.
    mtd const writtenByteCount()->u64 => .writer.writtenByteCount()

    // Converts and appends one video picture at the next exact frame slot.
    //
    // `slot` must start at index and decode time zero and then continue without gaps. Submit
    // the previous picture again for a dropped capture slot. Invalid slots and pictures leave
    // the video sequence count unchanged. Audio may be appended before or after a video call.
    mtd addFrame(image: const *Image, slot: FrameSlot) fail
    {
        if .ended do
            fail BadParameterError{"cannot append to a finished software recording"}
        if slot.index != .frameCount or slot.decodeTime != .nextVideoTime or not slot.duration do
            fail BadParameterError{"software recording needs consecutive video slots"}
        if slot.decodeTime > Swag.U64.Max - .videoOffset or
           slot.duration > Swag.U64.Max - slot.decodeTime - .videoOffset do
            fail OverflowError{"software recording video time overflows"}
        try .nv12.convertFrom(image)
        let packet = try .video.encode(&.nv12, slot.decodeTime + .videoOffset, slot.duration)
        try .writer.addPacket(packet)
        .frameCount += 1
        .nextVideoTime = slot.decodeTime + slot.duration
    }

    // Fills one missed capture slot with the last converted picture without reading the screen.
    //
    // The slot must directly follow the last written video slot. A recorder can call this once
    // for each gap reported by [[Video.FramePacer]] while a screen source is unavailable.
    mtd repeatLastFrame(slot: FrameSlot) fail
    {
        if .ended or not .frameCount do
            fail BadParameterError{"software recording has no live picture to repeat"}
        if slot.index != .frameCount or slot.decodeTime != .nextVideoTime or not slot.duration do
            fail BadParameterError{"software recording needs consecutive video slots"}
        if slot.decodeTime > Swag.U64.Max - .videoOffset or
           slot.duration > Swag.U64.Max - slot.decodeTime - .videoOffset do
            fail OverflowError{"software recording video time overflows"}
        let packet = try .video.encode(&.nv12, slot.decodeTime + .videoOffset, slot.duration)
        try .writer.addPacket(packet)
        .frameCount += 1
        .repeatedFrames += 1
        .nextVideoTime = slot.decodeTime + slot.duration
    }

    // Encodes any number of complete interleaved PCM16 source frames into AAC packets.
    //
    // Input is consumed synchronously; the writer copies completed AAC packets before this
    // method returns. An invalid channel layout leaves the audio encoder unchanged.
    mtd addAudioFrames(samples: const [..] s16, trackIndex: u32 = 0) fail
    {
        if .ended do
            fail BadParameterError{"cannot append to a finished software recording"}
        if trackIndex >= .tracks.count do
            fail BadParameterError{"software recording has no audio track at this index"}
        let track = &.tracks[trackIndex]
        let channels = track.encoder.channelCount()
        if samples.count % channels do
            fail BadParameterError{"software recording needs complete audio frames"}
        var cursor = 0'u64
        while cursor < samples.count
        {
            let consumed = try track.encoder.push(samples[cursor until samples.count], &track.packet)
            cursor += consumed * channels
            if track.packet.count do
                try .writer.addAudioPacket(EncodedPacket{track.packet.toSlice(),
                                                         track.encoder.lastPacketStartSample(),
                                                         track.encoder.lastPacketStartSample(),
                                                         1_024, true}, trackIndex)
        }
    }

    // Flushes completed fragments so an interrupted process leaves a playable media prefix.
    mtd flush() fail
    {
        try .writer.flush()
    }

    // Drains audio and finalizes the MP4 recording; repeated calls are harmless.
    //
    // At least one video frame must have been submitted. A short last audio block is padded
    // for AAC encoding; the final MP4 edit list omits that padding and encoder priming.
    // FFmpeg versions that ignore edit lists in fragmented MP4 may still expose the padding.
    mtd end() fail
    {
        if .ended do
            return
        if not .frameCount do
            fail BadParameterError{"software recording needs at least one video frame"}
        for index in .tracks.count
        {
            let track = &.tracks[index]
            while try track.encoder.finish(&track.packet)
            {
                try .writer.addAudioPacket(EncodedPacket{track.packet.toSlice(),
                                                         track.encoder.lastPacketStartSample(),
                                                         track.encoder.lastPacketStartSample(),
                                                         1_024, true}, cast(u32, index))
            }
        }
        if .tracks.count
        {
            var frameCounts: Array'u64
            for &track in .tracks do
                frameCounts.add(track.encoder.inputFrameCount())
            try .writer.setPresentationEdits(.videoOffset, frameCounts.toSlice())
        }
        try .writer.end()
        .ended = true
    }
}
