#global if #command == Swag.CompilerCommand.Test

using Core

private func aacTestPackets(path: string)->Array'SoundPacket fail
{
    let bytes  = try File.readAllBytes(path)
    var result: retval
    var offset = 0'u64
    while offset < bytes.count
    {
        if bytes.count - offset < 7 or bytes[offset] != 0xFF or bytes[offset + 1] & 0xF6 != 0xF0 do
            fail InvalidFormatError{"AAC test fixture has an invalid ADTS header"}
        let frameSize = (cast(u32) (bytes[offset + 3] & 3) << 11) | (cast(u32) bytes[offset + 4] << 3) | (cast(u32) bytes[offset + 5] >> 5)
        if frameSize < 7 or frameSize > bytes.count - offset do
            fail InvalidFormatError{"AAC test fixture has a truncated ADTS frame"}
        result.add({offset + 7, frameSize - 7, 1024})
        offset += frameSize
    }

    return result
}

private func aacTestSound()->SoundFile fail
{
    const Config: [2] u8 = [0x12, 0x10]
    let path    = audioGetTestDataPath("aac-lc-stereo-44100.aac")
    let packets = try aacTestPackets(path)
    return SoundFile.openPacketStream(path, .AacLc, 44_100, 2, packets.count * 1024, packets.toSlice(), Config)
}

private func aacTestSound51()->SoundFile fail
{
    const Config: [2] u8 = [0x11, 0xB0]
    let path    = audioGetTestDataPath("aac-lc-5.1-48000.aac")
    let packets = try aacTestPackets(path)
    return SoundFile.openPacketStream(path, .AacLc, 48_000, 6, packets.count * 1024, packets.toSlice(), Config)
}

private func aacTonePower(samples: const [*] s16, firstFrame, frameCount, channels, channel: u64, sampleRate, frequency: f64)->f64
{
    var real, imaginary: f64
    for frame in frameCount
    {
        let angle = 2.0 * Math.ConstF64.Pi * frequency * cast(f64) frame / sampleRate
        let value = cast(f64) samples[(firstFrame + frame) * channels + channel]
        real      += value * Math.cos(angle)
        imaginary -= value * Math.sin(angle)
    }

    return real * real + imaginary * imaginary
}

#test
{
    var sound = expect aacTestSound()
    Swag.assert(sound.sampleEncoding() == .AacLc)
    Swag.assert(sound.sampleRateHz() == 44_100 and sound.numChannels() == 2)
    Swag.assert(sound.packetCount() > 40 and !sound.isDataPreloaded())

    // Logical payload reads cross the ADTS headers between sparse access units instead of
    // treating their file offsets as a contiguous byte stream.
    let source = expect File.readAllBytes(audioGetTestDataPath("aac-lc-stereo-44100.aac"))
    let first  = expect sound.packet(0)
    let second = expect sound.packet(1)
    let joined = expect sound.readPayload(first.byteSize - 3, 6)
    Swag.assert(joined[0] == source[first.sourceOffset + first.byteSize - 3])
    Swag.assert(joined[2] == source[first.sourceOffset + first.byteSize - 1])
    Swag.assert(joined[3] == source[second.sourceOffset])
    Swag.assert(joined[5] == source[second.sourceOffset + 2])

    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice   = (expect Voice.create(&sound))!
    let decoded = expect voice.readBuffer()
    Swag.assert(decoded.size == 4 * 1024 * 2 * #sizeof(s16))
    let samples = cast(const [*] s16) decoded.buffer!
    var peak    = 0's32
    for index in decoded.size / #sizeof(s16) do
        peak = Math.max(peak, Math.abs(cast(s32) samples[index]))
    Swag.assert(peak > 1_000)
    Swag.assert(aacTonePower(samples, 2_048, 2_048, 2, 0, 44_100, 440) > 10.0 * aacTonePower(samples, 2_048, 2_048, 2, 0, 44_100, 660))
    Swag.assert(aacTonePower(samples, 2_048, 2_048, 2, 1, 44_100, 660) > 10.0 * aacTonePower(samples, 2_048, 2_048, 2, 1, 44_100, 440))

    discard expect voice.seekSampleFrame(5 * 1024 + 256)
    let afterSeek = expect voice.readBuffer()
    Swag.assert(afterSeek.size == (4 * 1024 - 256) * 2 * #sizeof(s16))
    Swag.assert(voice.streamPacketIdx == 9)
    voice.destroy()
}

// AAC channel configuration 6 arrives as C, L, R, SL, SR, LFE. The packet codec emits the WAVE
// 5.1 order L, R, C, LFE, SL, SR that the backend speaker mask describes.
#test
{
    var sound = expect aacTestSound51()
    Swag.assert(sound.numChannels() == 6 and sound.speakerChannelMask() == 0x3F)
    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = (expect Voice.create(&sound))!
    defer voice.destroy()

    let decoded = expect voice.readBuffer()
    Swag.assert(decoded.size == 4 * 1024 * 6 * #sizeof(s16))
    let samples = cast(const [*] s16) decoded.buffer!
    const Frequencies: [6] f64 = [300, 400, 500, 600, 700, 800]
    for channel in 6
    {
        // The AAC encoder deliberately low-passes LFE; its 600 Hz probe is almost entirely
        // removed, so channel 3 is checked for decoded activity rather than tone dominance.
        if channel == 3 do
            continue
        let wanted = aacTonePower(samples, 2_048, 2_048, 6, channel, 48_000, Frequencies[channel])
        let other  = aacTonePower(samples, 2_048, 2_048, 6, channel, 48_000, Frequencies[(channel + 1) % 6])
        Swag.assert(wanted > 8.0 * other)
    }

    var lfePeak = 0's32
    for frame in 4 * 1024 do
        lfePeak = Math.max(lfePeak, Math.abs(cast(s32) samples[frame * 6 + 3]))
    Swag.assert(lfePeak > 100)
}

// Codec priming is part of the decoded timeline, but not of the audible one. Opening a stream
// with leading trim must therefore produce exactly the same first samples as seeking an otherwise
// identical stream to that decoded position, including the AAC overlap pre-roll.
#test
{
    const Trim           = 1280'u64
    const Config: [2] u8 = [0x12, 0x10]
    let path    = audioGetTestDataPath("aac-lc-stereo-44100.aac")
    let packets = expect aacTestPackets(path)
    var full    = expect SoundFile.openPacketStream(path, .AacLc, 44_100, 2, packets.count * 1024, packets.toSlice(), Config)
    var trimmed = expect SoundFile.openPacketStream(path, .AacLc, 44_100, 2, packets.count * 1024, packets.toSlice(), Config, {leadingTrimFrames: Trim})
    Swag.assert(trimmed.sampleFrameCount() == full.sampleFrameCount() - Trim)
    Swag.assert(full.timelineStartSeconds() == 0)

    var window = expect SoundFile.openPacketStream(path, .AacLc, 44_100, 2, packets.count * 1024, packets.toSlice(), Config, {timelineStartSeconds: 125.5, displayName: "Commentary", language: "eng"})
    Swag.assert(window.timelineStartSeconds() == 125.5 and window.sampleFrameCount() == full.sampleFrameCount())
    Swag.assert(window.displayName() == "Commentary" and window.language() == "eng")
    discard catch SoundFile.openPacketStream(path, .AacLc, 44_100, 2, packets.count * 1024, packets.toSlice(), Config, {timelineStartSeconds: -1}) as invalidTimeline
    Swag.assert(invalidTimeline is BadParameterError)

    discard expect createNoSoundEngine()
    defer destroyEngine()
    let fullVoice    = (expect Voice.create(&full))!
    let trimmedVoice = (expect Voice.create(&trimmed))!
    defer fullVoice.destroy()
    defer trimmedVoice.destroy()
    discard expect fullVoice.seekSampleFrame(Trim)
    let expected = expect fullVoice.readBuffer()
    let actual   = expect trimmedVoice.readBuffer()
    Swag.assert(actual.size == expected.size)
    Swag.assert(Memory.compare(actual.buffer!, expected.buffer!, actual.size) == 0)
    var firstRead: Array'u8
    firstRead.resize(actual.size)
    Memory.copy(firstRead.buffer!, actual.buffer!, actual.size)

    discard expect trimmedVoice.seekSampleFrame(0)
    let rewound = expect trimmedVoice.readBuffer()
    Swag.assert(rewound.size == actual.size)
    Swag.assert(Memory.compare(rewound.buffer!, firstRead.buffer!, actual.size) == 0)
}

#test
{
    var sound = expect aacTestSound()
    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = (expect Voice.create(&sound))!
    discard expect voice.play()
    discard expect voice.updateNoSound()
    Swag.assert(voice.playbackSampleFrame() == sound.sampleFrameCount())
    Swag.assert(!(cast(*NoSoundVoice) voice.handle!).isPlaying)
    voice.destroy()
}

// A seek performed while paused discards the queued buffers, so playing again has to fill them.
// Leaving the voice marked as primed made the next play start the backend on an empty queue: it
// reported itself playing and stayed silent for good, which is what a player hears after its
// first seek.
#test
{
    var sound = expect aacTestSound()
    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = (expect Voice.create(&sound))!
    defer voice.destroy()

    discard expect voice.play()
    Swag.assert(voice.hasState(.PlayedOnce))

    discard expect voice.pause()
    discard expect voice.seekSampleFrame(2 * 1024)
    Swag.assert(!voice.hasState(.PlayedOnce))

    discard expect voice.play()
    Swag.assert(voice.hasState(.PlayedOnce))
    discard expect voice.updateNoSound()
    Swag.assert(voice.playbackSampleFrame() > 2 * 1024)
}

// An `.aac` file opens on its own, and the index it builds is the one this suite builds by hand.
//
// The hand-built stream is what every other test here decodes, so proving the reader agrees with
// it proves the reader without decoding anything twice.
#test
{
    let path   = audioGetTestDataPath("aac-lc-stereo-44100.aac")
    let wanted = expect aacTestPackets(path)
    var sound  = expect SoundFile.load(path.toString())

    Swag.assert(sound.sampleEncoding() == .AacLc)
    Swag.assert(sound.sampleRateHz() == 44_100 and sound.numChannels() == 2)
    Swag.assert(sound.packetCount() == wanted.count)
    Swag.assert(sound.sampleFrameCount() == wanted.count * 1024)
    Swag.assert(sound.decoderConfig.count == 2 and sound.decoderConfig[0] == 0x12 and sound.decoderConfig[1] == 0x10)
    for index in wanted.count
    {
        let got = expect sound.packet(index)
        Swag.assert(got.sourceOffset == wanted[index].sourceOffset)
        Swag.assert(got.byteSize == wanted[index].byteSize)
        Swag.assert(got.sampleFrameCount == wanted[index].sampleFrameCount)
    }
}

// A six-channel stream states its own configuration in every frame, and the reader turns that
// into the two bytes a codec expects.
#test
{
    let path  = audioGetTestDataPath("aac-lc-5.1-48000.aac")
    var sound = expect SoundFile.load(path.toString())
    Swag.assert(sound.sampleRateHz() == 48_000 and sound.numChannels() == 6)
    Swag.assert(sound.speakerChannelMask() == 0x3F)
    Swag.assert(sound.decoderConfig.count == 2 and sound.decoderConfig[0] == 0x11 and sound.decoderConfig[1] == 0xB0)
}
