//! Format: software H.264 and AAC-LC recording into fragmented MP4.
//! Supported: sequential constant-rate frame slots and arbitrarily chunked mono/stereo PCM16.
//! Role: This file connects the portable encoders to a recoverable audiovisual container.
//
#global namespace Mp4
#global export

using Core, Core.Errors, Pixel, Audio

// Records RGB pictures and PCM16 sound as a fragmented MP4 without codec libraries.
//
// The caller assigns video slots with [[Video.FramePacer]]. Every slot, including a repeated
// picture for a missed capture, must be submitted in order. Sound may arrive in arbitrary
// complete-frame chunks. The first video packet begins one AAC priming packet after audio so
// [[Video.Reader]] removes the encoder's 1024 delayed samples and aligns audible frame zero
// with video frame zero. `end` drains the audio transform before finalizing the file. Internal
// picture, PCM and packet storage stays bounded as the recording grows.
#[Swag.NoCopy]
#[Swag.Opaque]
struct SoftwareRecording
{
    private
    {
        writer:        FragmentedWriter
        video:         H264.Encoder
        audio:         Aac.StreamEncoder
        nv12:          Nv12Frame
        audioPacket:   Array'u8
        videoOffset:   u64
        nextVideoTime: u64
        frameCount:    u64
        ended:         bool
    }
}

impl SoftwareRecording
{
    // Creates a software audiovisual recorder and writes the MP4 initialization movie.
    //
    // Video dimensions must be positive and even. The video timescale must express each
    // intended frame duration. AAC accepts mono/stereo 44.1 or 48 kHz PCM16. The writer owns
    // the output path; completed fragments stay playable after an interrupted process.
    func create(path: string, width, height: s32, videoTimescale: u32,
                audioRate: u32, audioChannels: u16, keyInterval: u32 = 60,
                bandwidth: Aac.Bandwidth = .Full,
                options: FragmentedOptions = {})->SoftwareRecording fail
    {
        var result: #returntype
        result.video = try H264.Encoder.create(width, height, keyInterval)
        result.audio = try Aac.StreamEncoder.create(audioRate, audioChannels, bandwidth)
        let clock = try Timebase.create(videoTimescale)
        result.videoOffset = try clock.convertFrom(result.audio.encoderDelayFrames(), audioRate)
        result.writer = try FragmentedWriter.createWithAudio(path, width, height, videoTimescale,
                                                             result.video.decoderConfig(),
                                                             FragmentedAudioConfig{audioRate, audioChannels,
                                                                                   result.audio.decoderConfig()},
                                                             options)
        return result
    }

    // Returns the AAC priming offset added to each submitted video slot, in video ticks.
    mtd const videoPrerollTicks()->u64 => .videoOffset

    // Returns the number of accepted video frames, including caller-supplied repeats.
    mtd const videoFrameCount()->u64 => .frameCount

    // Returns the number of source PCM16 frames consumed so far.
    mtd const audioInputFrameCount()->u64 => .audio.inputFrameCount()

    // Returns the number of AAC-LC packets submitted, including the final drain packet.
    mtd const audioPacketCount()->u64 => .audio.packetCount()

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

    // Encodes any number of complete interleaved PCM16 source frames into AAC packets.
    //
    // Input is consumed synchronously; the writer copies completed AAC packets before this
    // method returns. An invalid channel layout leaves the audio encoder unchanged.
    mtd addAudioFrames(samples: const [..] s16) fail
    {
        if .ended do
            fail BadParameterError{"cannot append to a finished software recording"}
        let channels = .audio.channelCount()
        if samples.count % channels do
            fail BadParameterError{"software recording needs complete audio frames"}
        var cursor = 0'u64
        while cursor < samples.count
        {
            let consumed = try .audio.push(samples[cursor until samples.count], &.audioPacket)
            cursor += consumed * channels
            if .audioPacket.count do
                try .writer.addAudioPacket(EncodedPacket{.audioPacket.toSlice(),
                                                         .audio.lastPacketStartSample(),
                                                         .audio.lastPacketStartSample(), 1_024, true})
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
    // to a full AAC packet; its valid input count remains available through
    // `audioInputFrameCount`, while the container currently plays that short padded tail.
    mtd end() fail
    {
        if .ended do
            return
        if not .frameCount do
            fail BadParameterError{"software recording needs at least one video frame"}
        while try .audio.finish(&.audioPacket)
        {
            try .writer.addAudioPacket(EncodedPacket{.audioPacket.toSlice(),
                                                     .audio.lastPacketStartSample(),
                                                     .audio.lastPacketStartSample(), 1_024, true})
        }
        try .writer.end()
        .ended = true
    }
}
