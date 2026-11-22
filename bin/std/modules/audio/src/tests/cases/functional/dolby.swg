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

private func ac3TestFrameWithBandwidth(bandwidth, exponentStrategy: u32, invalidDelta: bool)->Array'u8
{
    var frame: Array'u8
    var bits = 0'u64
    ac3TestAppendBits(&frame, &bits, 0x0B77, 16)     // Sync word.
    ac3TestAppendBits(&frame, &bits, 0, 16)          // CRC.
    ac3TestAppendBits(&frame, &bits, 0, 2)           // 48 kHz.
    ac3TestAppendBits(&frame, &bits, 0, 6)           // 32 kbps, 128-byte frame.
    ac3TestAppendBits(&frame, &bits, 8, 5)           // AC-3 bit-stream id.
    ac3TestAppendBits(&frame, &bits, 0, 3)           // Bit-stream mode.
    ac3TestAppendBits(&frame, &bits, 1, 3)           // Mono.
    ac3TestAppendBits(&frame, &bits, 0, 1)           // No LFE.
    ac3TestAppendBits(&frame, &bits, 0, 5)           // Dialnorm.
    ac3TestAppendBits(&frame, &bits, 0, 1)           // No compression word.
    ac3TestAppendBits(&frame, &bits, 0, 1)           // No language code.
    ac3TestAppendBits(&frame, &bits, 0, 1)           // No audio production info.
    ac3TestAppendBits(&frame, &bits, 0, 2)           // Copyright and original bits.
    ac3TestAppendBits(&frame, &bits, 0, 3)           // No extended BSI or additional bytes.

    ac3TestAppendBits(&frame, &bits, 0, 1)     // Block switching.
    ac3TestAppendBits(&frame, &bits, 0, 1)     // Dither.
    ac3TestAppendBits(&frame, &bits, 0, 1)     // No dynamic range word.
    ac3TestAppendBits(&frame, &bits, 0, 1)     // No coupling.
    ac3TestAppendBits(&frame, &bits, exponentStrategy, 2)
    if exponentStrategy
    {
        ac3TestAppendBits(&frame, &bits, bandwidth, 6)
        ac3TestAppendBits(&frame, &bits, 12, 4)     // Absolute exponent.
        let end    = 37 + 3 * cast(s32, (bandwidth + 12))
        let groups = cast(u32, ((end - 1 + 2) / 3))
        for groups do
            ac3TestAppendBits(&frame, &bits, 62, 7)     // Keep every exponent at the absolute value.
        ac3TestAppendBits(&frame, &bits, 0, 2)     // Gain range.
    }

    ac3TestAppendBits(&frame, &bits, 1, 1)      // First block has allocation parameters.
    ac3TestAppendBits(&frame, &bits, 0, 11)     // Allocation parameters.
    ac3TestAppendBits(&frame, &bits, 1, 1)      // SNR offsets present.
    ac3TestAppendBits(&frame, &bits, 15, 6)     // Coarse SNR: zero bit allocation.
    ac3TestAppendBits(&frame, &bits, 0, 7)      // Fine SNR and fast gain.
    ac3TestAppendBits(&frame, &bits, invalidDelta ? 1 : 0, 1)
    if invalidDelta
    {
        ac3TestAppendBits(&frame, &bits, 1, 2)     // New delta allocation.
        ac3TestAppendBits(&frame, &bits, 1, 2)     // Two segments.
        ac3TestAppendBits(&frame, &bits, 31, 5)
        ac3TestAppendBits(&frame, &bits, 15, 4)
        ac3TestAppendBits(&frame, &bits, 0, 3)
        ac3TestAppendBits(&frame, &bits, 31, 5)
        ac3TestAppendBits(&frame, &bits, 1, 4)
        ac3TestAppendBits(&frame, &bits, 0, 3)
    }

    ac3TestAppendBits(&frame, &bits, 0, 1)     // No skip field.

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

private func dolbyRequireInvalidFile(path: String, bytes: const [..] u8)
{
    discard expect File.writeAllBytes(path.toString(), bytes)
    var error: Swag.Error
    discard catch SoundFile.load(path.toString()) as error
    Swag.require(error.value() is InvalidFormatError)
}

private func dolbyRequireDecodeFormatError(path: string, encoding: SoundFileEncoding, frameFrames: u32, bytes: const [..] u8, expectedMessage: string)
{
    discard expect File.writeAllBytes(path, bytes)
    let packets: [1] SoundPacket = [SoundPacket{0, cast(u32, bytes.count), frameFrames}]
    var config:  Array'u8
    var sound = expect SoundFile.openPacketStream(path, encoding, 48_000, 1, frameFrames, packets, config.toSlice())
    var error:   Swag.Error
    discard catch sound.decodePcm16(func(_)->bool => true) as error
    Swag.require(error.value() is InvalidFormatError)
    Swag.require(Errors.message(error.value()) == expectedMessage)
}

private func eac3TestChannelBandwidthFrame(bandwidth: u32, invalidDelta: bool)->Array'u8
{
    var frame: Array'u8
    var bits = 0'u64
    ac3TestAppendBits(&frame, &bits, 0x0B77, 16)     // Sync word.
    ac3TestAppendBits(&frame, &bits, 0, 2)           // Independent substream.
    ac3TestAppendBits(&frame, &bits, 0, 3)           // Substream id.
    ac3TestAppendBits(&frame, &bits, 255, 11)        // 512-byte frame.
    ac3TestAppendBits(&frame, &bits, 0, 2)           // 48 kHz.
    ac3TestAppendBits(&frame, &bits, 3, 2)           // Six blocks.
    ac3TestAppendBits(&frame, &bits, 1, 3)           // Mono.
    ac3TestAppendBits(&frame, &bits, 0, 1)           // No LFE.
    ac3TestAppendBits(&frame, &bits, 16, 5)          // E-AC-3 bit-stream id.
    ac3TestAppendBits(&frame, &bits, 0, 5)           // Dialnorm.
    ac3TestAppendBits(&frame, &bits, 0, 1)           // No compression word.
    ac3TestAppendBits(&frame, &bits, 0, 1)           // No mixing metadata.
    ac3TestAppendBits(&frame, &bits, 0, 1)           // No information metadata.
    ac3TestAppendBits(&frame, &bits, 0, 1)           // No additional BSI bytes.

    ac3TestAppendBits(&frame, &bits, 1, 1)     // Six-block exponent strategy.
    ac3TestAppendBits(&frame, &bits, 0, 1)     // No adaptive hybrid transform.
    ac3TestAppendBits(&frame, &bits, 0, 2)     // SNR strategy zero.
    ac3TestAppendBits(&frame, &bits, 0, 1)     // No transient pre-noise processing.
    ac3TestAppendBits(&frame, &bits, 1, 1)     // Read per-block block-switch flags.
    ac3TestAppendBits(&frame, &bits, 1, 1)     // Read per-block dither flags.
    ac3TestAppendBits(&frame, &bits, 0, 1)     // Reuse allocation defaults.
    ac3TestAppendBits(&frame, &bits, 0, 1)     // No fast gain codes.
    ac3TestAppendBits(&frame, &bits, invalidDelta ? 1 : 0, 1)
    ac3TestAppendBits(&frame, &bits, 0, 1)     // No skipped data.
    ac3TestAppendBits(&frame, &bits, 0, 1)     // No spectral-extension attenuation.
    for block in 6 do
        ac3TestAppendBits(&frame, &bits, block == 0 ? 1 : 0, 2)     // Decode exponents in block zero only.
    ac3TestAppendBits(&frame, &bits, 0, 5)      // Converter strategy.
    ac3TestAppendBits(&frame, &bits, 15, 6)     // Zero bit-allocation SNR offset.
    ac3TestAppendBits(&frame, &bits, 0, 4)      // Fine SNR.
    ac3TestAppendBits(&frame, &bits, 0, 1)      // No block start information.

    for block in 6
    {
        ac3TestAppendBits(&frame, &bits, 0, 1)     // No block switching.
        ac3TestAppendBits(&frame, &bits, 0, 1)     // No dither.
        ac3TestAppendBits(&frame, &bits, 0, 1)     // No dynamic range word.
        ac3TestAppendBits(&frame, &bits, 0, 1)     // Keep spectral extension off.
        if not block
        {
            ac3TestAppendBits(&frame, &bits, bandwidth, 6)
            ac3TestAppendBits(&frame, &bits, 24, 4)     // Minimize mantissas if validation is missing.
            let end    = 37 + 3 * cast(s32, (bandwidth + 12))
            let groups = cast(u32, ((end + 1) / 3))
            for groups do
                ac3TestAppendBits(&frame, &bits, 62, 7)     // Keep each exponent unchanged.
            ac3TestAppendBits(&frame, &bits, 0, 2)     // Gain range.
        }

        ac3TestAppendBits(&frame, &bits, 0, 1)     // No block start information.
        if invalidDelta
        {
            ac3TestAppendBits(&frame, &bits, block == 0 ? 1 : 0, 1)
            if not block
            {
                ac3TestAppendBits(&frame, &bits, 1, 2)     // New delta allocation.
                ac3TestAppendBits(&frame, &bits, 1, 3)     // Two segments.
                ac3TestAppendBits(&frame, &bits, 31, 5)
                ac3TestAppendBits(&frame, &bits, 15, 4)
                ac3TestAppendBits(&frame, &bits, 0, 3)
                ac3TestAppendBits(&frame, &bits, 31, 5)
                ac3TestAppendBits(&frame, &bits, 1, 4)
                ac3TestAppendBits(&frame, &bits, 0, 3)
            }
        }
    }

    while frame.count < 512 do
        frame.add(0)
    return frame
}

// A first AC-3 block cannot reuse channel exponents before any packet state exists.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("dolby-first-exponent-reuse-%.ac3", Guid128.random()))
    defer discard catch File.delete(path)
    let frame = ac3TestFrameWithBandwidth(0, 0, false)
    dolbyRequireDecodeFormatError(path,
                                  .Ac3,
                                  1536,
                                  frame.toSlice(),
                                  "Dolby bit-allocation range is invalid")
}

// Delta segments that extend past the active band range fail before indexing the mask table.
#test
{
    let ac3Path = Path.combine(Env.getSpecialDirectory(.Temp),
                               Format.toString("dolby-delta-ac3-%.ac3", Guid128.random()))
    defer discard catch File.delete(ac3Path)
    let ac3Frame = ac3TestFrameWithBandwidth(0, 1, true)
    dolbyRequireDecodeFormatError(ac3Path,
                                  .Ac3,
                                  1536,
                                  ac3Frame.toSlice(),
                                  "Dolby delta allocation segment exceeds the channel bands")

    let eac3Path = Path.combine(Env.getSpecialDirectory(.Temp),
                                Format.toString("dolby-delta-eac3-%.eac3", Guid128.random()))
    defer discard catch File.delete(eac3Path)
    let eac3Frame = eac3TestChannelBandwidthFrame(0, true)
    dolbyRequireDecodeFormatError(eac3Path,
                                  .Eac3,
                                  1536,
                                  eac3Frame.toSlice(),
                                  "Dolby delta allocation segment exceeds the channel bands")
}

// Elementary stream indexing rejects trailing bytes and midstream shape changes for both codecs.
#test
{
    let sourcePath = audioGetTestDataPath("ac3-5.1-48000.ac3")
    let testPath   = Path.combine(Env.getSpecialDirectory(.Temp),
                                  Format.toString("dolby-truncated-ac3-%.ac3", Guid128.random()))
    defer discard catch File.delete(testPath)
    let fixture = expect File.readAllBytes(sourcePath)

    var partialHeader = fixture
    partialHeader.add([0x0B'u8, 0x77, 0])
    dolbyRequireInvalidFile(testPath, partialHeader.toSlice())

    var truncatedFrame = fixture
    let frame = ac3TestFrameWithBandwidth(0, 1, false)
    truncatedFrame.add(Swag.makeSlice(&frame[0], 8))
    dolbyRequireInvalidFile(testPath, truncatedFrame.toSlice())

    var changedShape = fixture
    let packets      = expect ac3TestPackets(sourcePath)
    changedShape[packets[1].sourceOffset + 6] = 0x20
    dolbyRequireInvalidFile(testPath, changedShape.toSlice())
}

#test
{
    let sourcePath = audioGetTestDataPath("eac3-5.1-48000.eac3")
    let testPath   = Path.combine(Env.getSpecialDirectory(.Temp),
                                  Format.toString("dolby-truncated-eac3-%.eac3", Guid128.random()))
    defer discard catch File.delete(testPath)
    let fixture = expect File.readAllBytes(sourcePath)

    var partialHeader = fixture
    partialHeader.add([0x0B'u8, 0x77, 0])
    dolbyRequireInvalidFile(testPath, partialHeader.toSlice())

    var truncatedFrame = fixture
    let frame = eac3TestChannelBandwidthFrame(0, false)
    truncatedFrame.add(Swag.makeSlice(&frame[0], 8))
    dolbyRequireInvalidFile(testPath, truncatedFrame.toSlice())

    var changedShape = fixture
    let packets      = expect eac3TestPackets(sourcePath)
    let secondHeader = packets[1].sourceOffset + 4
    changedShape[secondHeader] = (changedShape[secondHeader] & 0xF1) | 0x02
    dolbyRequireInvalidFile(testPath, changedShape.toSlice())
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

// E-AC-3 rejects frames too short to contain the seven-byte mandatory BSI header.
#test
{
    for frameSizeCode in [0'u8, 2]     // Declare two bytes, then six bytes.
    {
        var frame: [8] u8
        frame[0] = 0x0B
        frame[1] = 0x77
        frame[3] = frameSizeCode

        let path = Path.combine(Env.getSpecialDirectory(.Temp),
                                Format.toString("dolby-short-eac3-%.eac3", Guid128.random()))
        defer discard catch File.delete(path)
        discard expect File.writeAllBytes(path, frame)

        var error: Swag.Error
        discard catch SoundFile.load(path.toString()) as error
        Swag.require(error.value() is InvalidFormatError)
    }
}

// The reserved reduced E-AC-3 sample-rate index is rejected by the reader.
#test
{
    var frame: [8] u8
    frame[0] = 0x0B
    frame[1] = 0x77
    frame[3] = 3        // Eight-byte frame, enough to reach the sampling-rate fields.
    frame[4] = 0xF0     // fscod 3, reserved fscod2 3.

    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("dolby-eac3-rate-%.eac3", Guid128.random()))
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path, frame)

    var error: Swag.Error
    discard catch SoundFile.load(path.toString()) as error
    Swag.require(error.value() is InvalidFormatError)
}

// Reduced-rate E-AC-3 maps each accepted rate to its corresponding core allocation row.
#test
{
    const ReducedRates: [3] u32 = [24_000, 22_050, 16_000]
    for reduced in ReducedRates.count
    {
        var packet: [8] u8
        packet[0] = 0x0B
        packet[1] = 0x77
        packet[3] = 3     // Eight-byte sync frame.
        packet[4] = cast(u8, 0xC4 | (reduced << 4))     // fscod 3 and fscod2.

        let header = Swag.makeSlice(&packet[0], packet.count)
        let info   = expect Dolby.eac3FrameInfo(header)
        let fscod  = cast(u32, packet[4] >> 6)
        let fscod2 = cast(u32, (packet[4] >> 4) & 3)
        Swag.require(info.sampleRate == ReducedRates[reduced])
        Swag.require(Dolby.eac3BitAllocationFscod(fscod, fscod2) == reduced)
    }
}

// E-AC-3 channel bandwidth codes above 60 are rejected before exponent arrays are filled.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("dolby-bandwidth-eac3-%.eac3", Guid128.random()))
    defer discard catch File.delete(path)

    for bandwidth in [61'u32, 62, 63]
    {
        let frame = eac3TestChannelBandwidthFrame(bandwidth, false)
        discard expect File.writeAllBytes(path, frame.toSlice())

        var packets: [1] SoundPacket = [SoundPacket{0, cast(u32, frame.count), 1536}]
        var config:  Array'u8
        var sound = expect SoundFile.openPacketStream(path.toString(),
                                                      .Eac3,
                                                      48_000,
                                                      1,
                                                      1536,
                                                      Swag.makeSlice(&packets[0], packets.count),
                                                      config.toSlice())
        var error: Swag.Error
        discard catch sound.decodePcm16(func(_)->bool => true) as error
        Swag.require(error.value() is InvalidFormatError)
        Swag.require(Errors.message(error.value()) == "E-AC-3 channel bandwidth code is reserved")
    }
}

// Reserved AC-3 bandwidth codes must fail before their exponent groups exceed the 256-bin arrays.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("dolby-bandwidth-%.ac3", Guid128.random()))
    defer discard catch File.delete(path.toString())

    for bandwidth in [62'u32, 63]
    {
        let bytes = ac3TestFrameWithBandwidth(bandwidth, 1, false)
        expect File.writeAllBytes(path.toString(), bytes.toSlice())
        var packets: Array'SoundPacket
        packets.add(SoundPacket{0, 128, 1536})
        var config: Array'u8
        var sound = expect SoundFile.openPacketStream(path.toString(), .Ac3, 48_000, 1, 1536, packets.toSlice(), config.toSlice())
        var error:  Swag.Error
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
