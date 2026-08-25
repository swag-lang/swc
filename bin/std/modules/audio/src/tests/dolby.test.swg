#global if #command == Swag.CompilerCommand.Test

using Core

private func ac3TestPackets(path: string)->Array'SoundPacket fail
{
    const BitRates: [19] u32 = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512, 576, 640]
    let bytes  = try File.readAllBytes(path)
    var result: retval
    var offset = 0'u64
    while offset < bytes.count
    {
        if bytes.count - offset < 5 or bytes[offset] != 0x0B or bytes[offset + 1] != 0x77 do
            fail InvalidFormatError{"AC-3 test fixture has an invalid sync frame"}
        let fscod    = bytes[offset + 4] >> 6
        let sizeCode = bytes[offset + 4] & 0x3F
        if fscod >= 3 or sizeCode >= 38 do
            fail InvalidFormatError{"AC-3 test fixture has a reserved frame-size code"}
        let bitRate   = BitRates[sizeCode >> 1]
        let frameSize = fscod == 0 ? 4 * bitRate : fscod == 1 ? 2 * ((320 * bitRate) / 147 + (sizeCode & 1)) : 6 * bitRate
        if frameSize > bytes.count - offset do
            fail InvalidFormatError{"AC-3 test fixture has a truncated sync frame"}
        result.add({offset, frameSize, 1536})
        offset += frameSize
    }

    return result
}

private func dolbyTonePower(samples: const [*] s16, firstFrame, frameCount, channels, channel: u64, frequency: f64)->f64
{
    var real, imaginary: f64
    for frame in frameCount
    {
        let angle = 2.0 * Math.ConstF64.Pi * frequency * cast(f64) frame / 48_000.0
        let value = cast(f64) samples[(firstFrame + frame) * channels + channel]
        real      += value * Math.cos(angle)
        imaginary -= value * Math.sin(angle)
    }

    return real * real + imaginary * imaginary
}

private func eac3TestPackets(path: string)->Array'SoundPacket fail
{
    let bytes  = try File.readAllBytes(path)
    var result: retval
    var offset = 0'u64
    while offset < bytes.count
    {
        if bytes.count - offset < 6 or bytes[offset] != 0x0B or bytes[offset + 1] != 0x77 do
            fail InvalidFormatError{"E-AC-3 test fixture has an invalid sync frame"}
        let frameSize = 2 * ((((cast(u32) bytes[offset + 2]) & 7) << 8) | bytes[offset + 3]) + 2
        let fscod     = bytes[offset + 4] >> 6
        const Blocks: [4] u32 = [1, 2, 3, 6]
        let blockCount = fscod == 3 ? 6 : Blocks[(bytes[offset + 4] >> 4) & 3]
        if frameSize > bytes.count - offset do
            fail InvalidFormatError{"E-AC-3 test fixture has a truncated sync frame"}
        result.add({offset, frameSize, blockCount * 256})
        offset += frameSize
    }

    return result
}

// The native AC-3 path decodes complete sync frames, preserves all 5.1 channels, and reorders
// AC-3's L,C,R,Ls,Rs,LFE bit-stream layout to the WAVE L,R,C,LFE,BL,BR speaker order.
#test
{
    let path    = audioGetTestDataPath("ac3-5.1-48000.ac3")
    let packets = expect ac3TestPackets(path)
    var config: Array'u8
    var sound   = expect SoundFile.openPacketStream(path, .Ac3, 48_000, 6, packets.count * 1536, packets.toSlice(), config.toSlice())
    @assert(sound.packetCount() == 16 and sound.speakerChannelMask() == 0x3F)

    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = (expect Voice.create(&sound))!
    defer voice.destroy()
    let decoded = expect voice.readBuffer()

    // The streaming buffer targets 100 ms. Three complete 32 ms AC-3 sync frames fit.
    @assert(decoded.size == 3 * 1536 * 6 * #sizeof(s16))
    let samples = cast(const [*] s16) decoded.buffer!
    const Frequencies: [6] f64 = [300, 400, 500, 600, 700, 800]
    for channel in 6
    {
        let wanted = dolbyTonePower(samples, 2048, 2048, 6, channel, Frequencies[channel])
        let other  = dolbyTonePower(samples, 2048, 2048, 6, channel, Frequencies[(channel + 1) % 6])
        @assert(wanted > 8.0 * other)
    }
}

// Stereo E-AC-3 exercises standard coupling, phase flags, and rematrixing. Those fields are
// absent from the 5.1 tone fixture but common in two-channel film tracks.
#test
{
    let path    = audioGetTestDataPath("eac3-stereo-48000.eac3")
    let packets = expect eac3TestPackets(path)
    var config: Array'u8
    var sound   = expect SoundFile.openPacketStream(path, .Eac3, 48_000, 2, packets.count * 1536, packets.toSlice(), config.toSlice())

    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = (expect Voice.create(&sound))!
    defer voice.destroy()
    let decoded = expect voice.readBuffer()
    @assert(decoded.size == 3 * 1536 * 2 * #sizeof(s16))
    let samples = cast(const [*] s16) decoded.buffer!
    @assert(dolbyTonePower(samples, 2048, 2048, 2, 0, 440) > 8.0 * dolbyTonePower(samples, 2048, 2048, 2, 0, 660))
    @assert(dolbyTonePower(samples, 2048, 2048, 2, 1, 660) > 8.0 * dolbyTonePower(samples, 2048, 2048, 2, 1, 440))
}

// The independent E-AC-3 path decodes the common six-block, standard-coupling profile and
// preserves the same 5.1 WAVE channel order as the AC-3 path.
#test
{
    let path    = audioGetTestDataPath("eac3-5.1-48000.eac3")
    let packets = expect eac3TestPackets(path)
    var config: Array'u8
    var sound   = expect SoundFile.openPacketStream(path, .Eac3, 48_000, 6, packets.count * 1536, packets.toSlice(), config.toSlice())
    @assert(sound.packetCount() == 16 and sound.speakerChannelMask() == 0x3F)

    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = (expect Voice.create(&sound))!
    defer voice.destroy()
    let decoded = expect voice.readBuffer()
    @assert(decoded.size == 3 * 1536 * 6 * #sizeof(s16))
    let samples = cast(const [*] s16) decoded.buffer!
    const Frequencies: [6] f64 = [300, 400, 500, 600, 700, 800]
    for channel in 6
    {
        let wanted = dolbyTonePower(samples, 2048, 2048, 6, channel, Frequencies[channel])
        let other  = dolbyTonePower(samples, 2048, 2048, 6, channel, Frequencies[(channel + 1) % 6])
        @assert(wanted > 8.0 * other)
    }
}

// An `.ac3` file opens on its own, and the index it builds is the one this suite builds by hand.
#test
{
    let path   = audioGetTestDataPath("ac3-5.1-48000.ac3")
    let wanted = expect ac3TestPackets(path)
    var sound  = expect SoundFile.load(path.toString())

    @assert(sound.sampleEncoding() == .Ac3)
    @assert(sound.sampleRateHz() == 48_000 and sound.numChannels() == 6)
    @assert(sound.packetCount() == wanted.count)
    for index in wanted.count
    {
        let got = expect sound.packet(index)
        @assert(got.sourceOffset == wanted[index].sourceOffset)
        @assert(got.byteSize == wanted[index].byteSize)
        @assert(got.sampleFrameCount == wanted[index].sampleFrameCount)
    }
}

// The same for `.eac3`, whose frames state their own length and block count.
#test
{
    let path   = audioGetTestDataPath("eac3-5.1-48000.eac3")
    let wanted = expect eac3TestPackets(path)
    var sound  = expect SoundFile.load(path.toString())

    @assert(sound.sampleEncoding() == .Eac3)
    @assert(sound.sampleRateHz() == 48_000 and sound.numChannels() == 6)
    @assert(sound.packetCount() == wanted.count)
    for index in wanted.count
    {
        let got = expect sound.packet(index)
        @assert(got.sourceOffset == wanted[index].sourceOffset)
        @assert(got.byteSize == wanted[index].byteSize)
        @assert(got.sampleFrameCount == wanted[index].sampleFrameCount)
    }

    var stereo = expect SoundFile.load(audioGetTestDataPath("eac3-stereo-48000.eac3").toString())
    @assert(stereo.numChannels() == 2 and stereo.sampleRateHz() == 48_000)
}
