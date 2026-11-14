#global if #command == Swag.CompilerCommand.Test

using Core

private func ac3TestAppendBits(bytes: *Array'u8, bitCount: *u64, value: u32, count: u32)
{
    for bit in count
    {
        if not (bitCount[] & 7) do
            bytes.add(0)
        let shift = count - bit - 1
        if (value >> shift) & 1 do
            bytes[bitCount[] >> 3] |= cast(u8, 1'u32 << (7 - cast(u32, bitCount[] & 7)))
        bitCount[] += 1
    }
}

private func ac3TestFrameWithBandwidth(bandwidth: u32)->Array'u8
{
    var frame: Array'u8
    var bits = 0'u64
    ac3TestAppendBits(&frame, &bits, 0x0B77, 16) // Sync word.
    ac3TestAppendBits(&frame, &bits, 0, 16) // CRC.
    ac3TestAppendBits(&frame, &bits, 0, 2) // 48 kHz.
    ac3TestAppendBits(&frame, &bits, 0, 6) // 32 kbps, 128-byte frame.
    ac3TestAppendBits(&frame, &bits, 8, 5) // AC-3 bit-stream id.
    ac3TestAppendBits(&frame, &bits, 0, 3) // Bit-stream mode.
    ac3TestAppendBits(&frame, &bits, 1, 3) // Mono.
    ac3TestAppendBits(&frame, &bits, 0, 1) // No LFE.
    ac3TestAppendBits(&frame, &bits, 0, 5) // Dialnorm.
    ac3TestAppendBits(&frame, &bits, 0, 1) // No compression word.
    ac3TestAppendBits(&frame, &bits, 0, 1) // No language code.
    ac3TestAppendBits(&frame, &bits, 0, 1) // No audio production info.
    ac3TestAppendBits(&frame, &bits, 0, 2) // Copyright and original bits.
    ac3TestAppendBits(&frame, &bits, 0, 3) // No extended BSI or additional bytes.

    ac3TestAppendBits(&frame, &bits, 0, 1) // Block switching.
    ac3TestAppendBits(&frame, &bits, 0, 1) // Dither.
    ac3TestAppendBits(&frame, &bits, 0, 1) // No dynamic range word.
    ac3TestAppendBits(&frame, &bits, 0, 1) // No coupling.
    ac3TestAppendBits(&frame, &bits, 1, 2) // Exponent strategy 1.
    ac3TestAppendBits(&frame, &bits, bandwidth, 6)
    ac3TestAppendBits(&frame, &bits, 12, 4) // Absolute exponent.
    for 87 do
        ac3TestAppendBits(&frame, &bits, 62, 7) // Keep every exponent at the absolute value.
    ac3TestAppendBits(&frame, &bits, 0, 2) // Gain range.
    ac3TestAppendBits(&frame, &bits, 1, 1) // First block has allocation parameters.
    ac3TestAppendBits(&frame, &bits, 0, 11) // Allocation parameters.
    ac3TestAppendBits(&frame, &bits, 1, 1) // SNR offsets present.
    ac3TestAppendBits(&frame, &bits, 15, 6) // Coarse SNR: zero bit allocation.
    ac3TestAppendBits(&frame, &bits, 0, 7) // Fine SNR and fast gain.
    ac3TestAppendBits(&frame, &bits, 0, 1) // No delta allocation.
    ac3TestAppendBits(&frame, &bits, 0, 1) // No skip field.

    while frame.count < 128 do
        frame.add(0)
    return frame
}

private func ac3TestPackets(path: string)->Array'SoundPacket fail
{
    const BitRates: [19] u32 = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512, 576, 640]
    let bytes  = try File.readAllBytes(path)
    var result: #returntype
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
        let frameSize = fscod == 0 ? 4 * bitRate :
                        fscod == 1 ? 2 * ((320 * bitRate) / 147 + (sizeCode & 1)) :
                        6 * bitRate
        if frameSize > bytes.count - offset do
            fail InvalidFormatError{"AC-3 test fixture has a truncated sync frame"}
        result.add(SoundPacket{offset, frameSize, 1536})
        offset += frameSize
    }

    return result
}

private func dolbyTonePower(samples: const [*] s16, firstFrame, frameCount, channels, channel: u64, frequency: f64)->f64
{
    var real, imaginary: f64
    for frame in frameCount
    {
        let angle = 2.0 * Math.ConstF64.Pi * frequency * cast(f64, frame) / 48_000.0
        let value = cast(f64, samples[(firstFrame + frame) * channels + channel])
        real      += value * Math.cos(angle)
        imaginary -= value * Math.sin(angle)
    }

    return real * real + imaginary * imaginary
}

private func eac3TestPackets(path: string)->Array'SoundPacket fail
{
    let bytes  = try File.readAllBytes(path)
    var result: #returntype
    var offset = 0'u64
    while offset < bytes.count
    {
        if bytes.count - offset < 6 or bytes[offset] != 0x0B or bytes[offset + 1] != 0x77 do
            fail InvalidFormatError{"E-AC-3 test fixture has an invalid sync frame"}
        let frameSize = 2 * (((cast(u32, bytes[offset + 2]) & 7) << 8) | bytes[offset + 3]) + 2
        let fscod     = bytes[offset + 4] >> 6
        const Blocks: [4] u32 = [1, 2, 3, 6]
        let blockCount = fscod == 3 ? 6 : Blocks[(bytes[offset + 4] >> 4) & 3]
        if frameSize > bytes.count - offset do
            fail InvalidFormatError{"E-AC-3 test fixture has a truncated sync frame"}
        result.add(SoundPacket{offset, frameSize, blockCount * 256})
        offset += frameSize
    }

    return result
}

// Dolby 2/1 audio uses the back-center speaker position rather than front-center.
#test
{
    var ac3Frame: [128] u8
    ac3Frame[0] = 0x0B
    ac3Frame[1] = 0x77
    ac3Frame[6] = 0x80     // acmod 4 (2/1), without LFE.
    let ac3Path = Path.combine(Env.getSpecialDirectory(.Temp),
                               Format.toString("dolby-acmod4-%.ac3", Guid128.random()))
    defer discard catch File.delete(ac3Path)
    discard expect File.writeAllBytes(ac3Path, ac3Frame)

    var ac3 = expect SoundFile.load(ac3Path)
    Swag.require(ac3.numChannels() == 3 and ac3.speakerChannelMask() == 0x0103)

    var eac3Frame: [128] u8
    eac3Frame[0] = 0x0B
    eac3Frame[1] = 0x77
    eac3Frame[3] = 63
    eac3Frame[4] = 0x08     // acmod 4 (2/1), without LFE.
    let eac3Path = Path.combine(Env.getSpecialDirectory(.Temp),
                                Format.toString("dolby-acmod4-%.eac3", Guid128.random()))
    defer discard catch File.delete(eac3Path)
    discard expect File.writeAllBytes(eac3Path, eac3Frame)

    var eac3 = expect SoundFile.load(eac3Path)
    Swag.require(eac3.numChannels() == 3 and eac3.speakerChannelMask() == 0x0103)
}

// Reserved AC-3 bandwidth codes must fail before their exponent groups exceed the 256-bin arrays.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("dolby-bandwidth-%.ac3", Guid128.random()))
    defer discard catch File.delete(path.toString())

    for bandwidth in [62'u32, 63]
    {
        let bytes = ac3TestFrameWithBandwidth(bandwidth)
        expect File.writeAllBytes(path.toString(), bytes.toSlice())
        var packets: Array'SoundPacket
        packets.add(SoundPacket{0, 128, 1536})
        var config: Array'u8
        var sound = expect SoundFile.openPacketStream(path.toString(), .Ac3, 48_000, 1, 1536, packets.toSlice(), config.toSlice())
        var error: Swag.Error
        discard catch sound.decodePcm16(func(_)->bool => true) as error
        Swag.require(error.value() is InvalidFormatError)
    }
}

// The native AC-3 path decodes complete sync frames, preserves all 5.1 channels, and reorders
// AC-3's L,C,R,Ls,Rs,LFE bit-stream layout to the WAVE L,R,C,LFE,BL,BR speaker order.
#test
{
    let path    = audioGetTestDataPath("ac3-5.1-48000.ac3")
    let packets = expect ac3TestPackets(path)
    var config: Array'u8
    var sound   = expect SoundFile.openPacketStream(path,
                                                    .Ac3,
                                                    48_000,
                                                    6,
                                                    packets.count * 1536,
                                                    packets.toSlice(),
                                                    config.toSlice())
    Swag.require(sound.packetCount() == 16 and sound.speakerChannelMask() == 0x3F)

    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = expect Voice.create(&sound)
    defer voice.destroy()
    let decoded = expect voice.readBuffer()

    // The streaming buffer targets 100 ms. Three complete 32 ms AC-3 sync frames fit.
    Swag.require(decoded.size == 3 * 1536 * 6 * #sizeof(s16))
    let samples = cast(const [*] s16, unwrap decoded.buffer)
    const Frequencies: [6] f64 = [300, 400, 500, 600, 700, 800]
    for channel in 6
    {
        let wanted = dolbyTonePower(samples, 2048, 2048, 6, channel, Frequencies[channel])
        let other  = dolbyTonePower(samples, 2048, 2048, 6, channel, Frequencies[(channel + 1) % 6])
        Swag.require(wanted > 8.0 * other)
    }
}

// Stereo E-AC-3 exercises standard coupling, phase flags, and rematrixing. Those fields are
// absent from the 5.1 tone fixture but common in two-channel film tracks.
#test
{
    let path    = audioGetTestDataPath("eac3-stereo-48000.eac3")
    let packets = expect eac3TestPackets(path)
    var config: Array'u8
    var sound   = expect SoundFile.openPacketStream(path,
                                                    .Eac3,
                                                    48_000,
                                                    2,
                                                    packets.count * 1536,
                                                    packets.toSlice(),
                                                    config.toSlice())

    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = expect Voice.create(&sound)
    defer voice.destroy()
    let decoded = expect voice.readBuffer()
    Swag.require(decoded.size == 3 * 1536 * 2 * #sizeof(s16))
    let samples = cast(const [*] s16, unwrap decoded.buffer)
    Swag.require(dolbyTonePower(samples, 2048, 2048, 2, 0, 440) > 8.0 * dolbyTonePower(samples, 2048, 2048, 2, 0, 660))
    Swag.require(dolbyTonePower(samples, 2048, 2048, 2, 1, 660) > 8.0 * dolbyTonePower(samples, 2048, 2048, 2, 1, 440))
}

// The independent E-AC-3 path decodes the common six-block, standard-coupling profile and
// preserves the same 5.1 WAVE channel order as the AC-3 path.
#test
{
    let path    = audioGetTestDataPath("eac3-5.1-48000.eac3")
    let packets = expect eac3TestPackets(path)
    var config: Array'u8
    var sound   = expect SoundFile.openPacketStream(path,
                                                    .Eac3,
                                                    48_000,
                                                    6,
                                                    packets.count * 1536,
                                                    packets.toSlice(),
                                                    config.toSlice())
    Swag.require(sound.packetCount() == 16 and sound.speakerChannelMask() == 0x3F)

    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = expect Voice.create(&sound)
    defer voice.destroy()
    let decoded = expect voice.readBuffer()
    Swag.require(decoded.size == 3 * 1536 * 6 * #sizeof(s16))
    let samples = cast(const [*] s16, unwrap decoded.buffer)
    const Frequencies: [6] f64 = [300, 400, 500, 600, 700, 800]
    for channel in 6
    {
        let wanted = dolbyTonePower(samples, 2048, 2048, 6, channel, Frequencies[channel])
        let other  = dolbyTonePower(samples, 2048, 2048, 6, channel, Frequencies[(channel + 1) % 6])
        Swag.require(wanted > 8.0 * other)
    }
}

// An `.ac3` file opens on its own, and the index it builds is the one this suite builds by hand.
#test
{
    let path   = audioGetTestDataPath("ac3-5.1-48000.ac3")
    let wanted = expect ac3TestPackets(path)
    var sound  = expect SoundFile.load(path.toString())

    Swag.require(sound.sampleEncoding() == .Ac3)
    Swag.require(sound.sampleRateHz() == 48_000 and sound.numChannels() == 6)
    Swag.require(sound.packetCount() == wanted.count)
    for index in wanted.count
    {
        let got = expect sound.packet(index)
        Swag.require(got.sourceOffset == wanted[index].sourceOffset)
        Swag.require(got.byteSize == wanted[index].byteSize)
        Swag.require(got.sampleFrameCount == wanted[index].sampleFrameCount)
    }
}

// The same for `.eac3`, whose frames state their own length and block count.
#test
{
    let path   = audioGetTestDataPath("eac3-5.1-48000.eac3")
    let wanted = expect eac3TestPackets(path)
    var sound  = expect SoundFile.load(path.toString())

    Swag.require(sound.sampleEncoding() == .Eac3)
    Swag.require(sound.sampleRateHz() == 48_000 and sound.numChannels() == 6)
    Swag.require(sound.packetCount() == wanted.count)
    for index in wanted.count
    {
        let got = expect sound.packet(index)
        Swag.require(got.sourceOffset == wanted[index].sourceOffset)
        Swag.require(got.byteSize == wanted[index].byteSize)
        Swag.require(got.sampleFrameCount == wanted[index].sampleFrameCount)
    }

    var stereo = expect SoundFile.load(audioGetTestDataPath("eac3-stereo-48000.eac3").toString())
    Swag.require(stereo.numChannels() == 2 and stereo.sampleRateHz() == 48_000)
}
