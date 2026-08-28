#global if #command == Swag.CompilerCommand.Test

using Core

private struct DtsTestBits
{
    bytes:    Array'u8
    bitCount: u64
}

private impl DtsTestBits
{
    mtd add(value: u64, count: u32)
    {
        for index in count
        {
            if !(.bitCount & 7) do
                .bytes.add(0)
            let source = count - 1 - index
            let target = cast(u32) (7 - (.bitCount & 7))
            .bytes[.bitCount >> 3] |= cast(u8) (((value >> source) & 1) << target)
            .bitCount              += 1
        }
    }
}

// Builds one mono, 256-frame Core packet whose first active high-frequency subband uses vector
// address 1. The payload is synthetic and contains no recording.
private func dtsVqPacket()->Array'u8
{
    var bits: DtsTestBits
    bits.add(0x7FFE8001, 32)
    bits.add(0, 1)       // Normal frame.
    bits.add(31, 5)      // No deficit samples.
    bits.add(0, 1)       // No CRC.
    bits.add(7, 7)       // Eight PCM blocks, or 256 sample frames.
    bits.add(31, 14)     // Fixed 32-byte packet.
    bits.add(0, 6)       // Mono.
    bits.add(13, 4)      // 48 kHz.
    bits.add(0, 5)       // 32 kbit/s rate index.
    bits.add(0, 5)       // Downmix, dynamic range, timestamp, auxiliary data, and HDCD.
    bits.add(0, 3)       // No extension-audio descriptor.
    bits.add(0, 1)       // No extension audio.
    bits.add(0, 1)       // Sync only at the end of the subsubframe.
    bits.add(0, 2)       // No LFE.
    bits.add(0, 1)       // No predictor history.
    bits.add(0, 1)       // Non-perfect synthesis filter.
    bits.add(0, 6)       // Encoder revision and copy history.
    bits.add(0, 3)       // 16-bit source PCM.
    bits.add(0, 1)       // No front sum/difference coding.
    bits.add(0, 1)       // No surround sum/difference coding.
    bits.add(0, 4)       // Dialog normalization and reserved bits.

    bits.add(0, 4)     // One subframe.
    bits.add(0, 3)     // One primary channel.
    bits.add(0, 5)     // Two active subbands.
    bits.add(0, 5)     // VQ begins at subband 1.
    bits.add(0, 3)     // No joint intensity.
    bits.add(0, 2)     // Transition selector.
    bits.add(6, 3)     // Direct seven-bit scale factors.
    bits.add(6, 3)     // Direct five-bit allocation indices.
    bits.add(1, 1)
    for book in 1'u32 until 5
    {
        discard book
        bits.add(3, 2)
    }

    for book in 5'u32 until 10
    {
        discard book
        bits.add(7, 3)
    }

    bits.add(0, 2)       // One subsubframe.
    bits.add(0, 3)       // No partial subsubframe.
    bits.add(0, 2)       // No prediction in either active subband.
    bits.add(0, 5)       // No scalar data in subband 0.
    bits.add(120, 7)     // High-frequency VQ scale.
    bits.add(1, 10)      // The first non-zero vector.
    bits.add(0xFFFF, 16)
    @assert(bits.bitCount <= 32 * 8)
    bits.bytes.resize(32)
    return bits.bytes
}

// Builds one mono Core packet whose first scalar subband uses predictor vector zero. The first
// residual is an impulse, so the following reconstructed samples exercise the four-tap feedback.
private func dtsPredictionPacket()->Array'u8
{
    var bits: DtsTestBits
    bits.add(0x7FFE8001, 32)
    bits.add(0, 1)
    bits.add(31, 5)
    bits.add(0, 1)
    bits.add(7, 7)
    bits.add(31, 14)
    bits.add(0, 6)
    bits.add(13, 4)
    bits.add(0, 5)
    bits.add(0, 5)
    bits.add(0, 3)
    bits.add(0, 1)
    bits.add(0, 1)
    bits.add(0, 2)
    bits.add(0, 1)
    bits.add(0, 1)
    bits.add(0, 6)
    bits.add(0, 3)
    bits.add(0, 1)
    bits.add(0, 1)
    bits.add(0, 4)

    bits.add(0, 4)     // One subframe.
    bits.add(0, 3)     // One primary channel.
    bits.add(0, 5)     // Two active subbands.
    bits.add(1, 5)     // Both subbands use scalar coding.
    bits.add(0, 3)     // No joint intensity.
    bits.add(0, 2)     // Transition selector.
    bits.add(6, 3)     // Direct seven-bit scale factors.
    bits.add(6, 3)     // Direct five-bit allocation indices.
    bits.add(1, 1)
    for book in 1'u32 until 5
    {
        discard book
        bits.add(3, 2)
    }

    for book in 5'u32 until 10
    {
        discard book
        bits.add(7, 3)
    }

    bits.add(0, 2)     // One subsubframe.
    bits.add(0, 3)
    bits.add(1, 1)     // Prediction in subband 0.
    bits.add(0, 1)
    bits.add(0, 12)     // Predictor vector zero.
    bits.add(8, 5)      // Five directly coded bits per sample in subband 0.
    bits.add(0, 5)
    bits.add(64, 7)     // Scalar scale factor.
    bits.add(1, 5)      // One impulse followed by seven zero residuals.
    for index in 1'u32 until 8
    {
        discard index
        bits.add(0, 5)
    }

    bits.add(0xFFFF, 16)
    @assert(bits.bitCount <= 32 * 8)
    bits.bytes.resize(32)
    return bits.bytes
}

private func dtsTonePower(samples: const [*] s16, firstFrame, frameCount, channels, channel: u64, frequency: f64)->f64
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

private func dtsAssertNativeStream(fileName: string, packetBytes: u32)
{
    let path  = audioGetTestDataPath(fileName)
    var sound = expect SoundFile.load(path.toString())

    @assert(sound.sampleEncoding() == .Dts)
    @assert(sound.sampleRateHz() == 48_000 and sound.numChannels() == 6)
    @assert(sound.speakerChannelMask() == 0x3F)
    @assert(sound.packetCount() == 47 and sound.sampleFrameCount() == 47 * 512)
    let first = expect sound.packet(0)
    @assert(first.sourceOffset == 0 and first.byteSize == packetBytes and first.sampleFrameCount == 512)

    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = (expect Voice.create(&sound))!
    defer voice.destroy()
    let decoded = expect voice.readBuffer()

    // The streaming buffer targets 100 ms. Nine complete 512-frame core packets fit.
    @assert(decoded.size == 9 * 512 * 6 * #sizeof(s16))
    let samples = cast(const [*] s16) decoded.buffer!
    const Frequencies: [6] f64 = [300, 400, 500, 60, 700, 800]
    for channel in 6
    {
        let wanted = dtsTonePower(samples, 2048, 2048, 6, channel, Frequencies[channel])
        let other  = dtsTonePower(samples, 2048, 2048, 6, channel, Frequencies[(channel + 1) % 6])
        @assert(wanted > 8.0 * other)
    }
}

// A native DTS Core stream is indexed from its frame headers, decoded through the packet-codec
// registry, and exposed in WAVE FL,FR,FC,LFE,BL,BR speaker order.
#test
{
    dtsAssertNativeStream("dts-5.1-48000.dts", 2012)
}

// The same coded frames survive 14-bit big-endian transport packing without changing their
// public track shape or channel content.
#test
{
    dtsAssertNativeStream("dts-5.1-48000-14be.dts", 2300)
}

// DTS-HD access units retain a complete core before their extension substream. A core decoder
// consumes only that prefix and produces exactly the same PCM as the standalone core frame.
#test
{
    let source = expect File.readAllBytes(audioGetTestDataPath("dts-5.1-48000.dts").toString())
    let info   = expect Dts.frameInfo(source.toSlice())

    var bytes: Array'u8
    bytes.add(source.toSlice()[0 until info.frameBytes])
    let extendedOffset = bytes.count
    bytes.add(source.toSlice()[0 until info.frameBytes])
    bytes.resize(bytes.count + 60)
    Memory.set(bytes.buffer! + bytes.count - 60, 0xA5, 60)

    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("audio-dts-extension-%.bin", Guid64.random()).toString())
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path, bytes.toSlice())

    let corePackets:     [1] SoundPacket = [{0, cast(u32) info.frameBytes, info.frames}]
    let extendedPackets: [1] SoundPacket = [{extendedOffset, cast(u32) info.frameBytes + 60, info.frames}]
    var config:          Array'u8
    let options                          = PacketStreamOptions{speakerMask: info.speakerMask}
    var core                             = expect SoundFile.openPacketStream(path, .Dts, info.sampleRate, info.channels, info.frames, corePackets, config.toSlice(), options)
    var extended                         = expect SoundFile.openPacketStream(path, .Dts, info.sampleRate, info.channels, info.frames, extendedPackets, config.toSlice(), options)

    discard expect createNoSoundEngine()
    defer destroyEngine()
    let coreVoice = (expect Voice.create(&core))!
    defer coreVoice.destroy()
    let extendedVoice = (expect Voice.create(&extended))!
    defer extendedVoice.destroy()
    let coreDecoded     = expect coreVoice.readBuffer()
    let extendedDecoded = expect extendedVoice.readBuffer()

    @assert(coreDecoded.size == cast(u64) info.frames * info.channels * #sizeof(s16))
    @assert(extendedDecoded.size == coreDecoded.size)
    @assert(Slice.equals(@mkslice(cast(const [*] u8) coreDecoded.buffer!, coreDecoded.size), @mkslice(cast(const [*] u8) extendedDecoded.buffer!, extendedDecoded.size)))
}

// A high-frequency VQ address is consumed and its band omitted instead of making the otherwise
// valid packet unsupported.
#test
{
    let bytes = dtsVqPacket()
    let info  = expect Dts.frameInfo(bytes.toSlice())
    let path  = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("audio-dts-vq-%.bin", Guid64.random()).toString())
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path, bytes.toSlice())

    let packets: [1] SoundPacket = [{0, cast(u32) bytes.count, info.frames}]
    var config:  Array'u8
    var sound = expect SoundFile.openPacketStream(path, .Dts, info.sampleRate, info.channels, info.frames, packets, config.toSlice(), {speakerMask: info.speakerMask})
    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = (expect Voice.create(&sound))!
    defer voice.destroy()
    let decoded = expect voice.readBuffer()
    @assert(decoded.size == cast(u64) info.frames * #sizeof(s16))
}

// ADPCM prediction is a normal Core coding tool, not an extension. A predicted scalar band must
// decode to audible PCM instead of making the packet unsupported.
#test
{
    let bytes = dtsPredictionPacket()
    let info  = expect Dts.frameInfo(bytes.toSlice())
    let path  = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("audio-dts-prediction-%.bin", Guid64.random()).toString())
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path, bytes.toSlice())

    let packets: [1] SoundPacket = [{0, cast(u32) bytes.count, info.frames}]
    var config:  Array'u8
    var sound = expect SoundFile.openPacketStream(path, .Dts, info.sampleRate, info.channels, info.frames, packets, config.toSlice(), {speakerMask: info.speakerMask})
    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = (expect Voice.create(&sound))!
    defer voice.destroy()
    let decoded = expect voice.readBuffer()
    let samples = @mkslice(cast(const [*] s16) decoded.buffer!, decoded.size / #sizeof(s16))
    var nonZero: u64
    for sample in samples where sample do
        nonZero += 1
    @assert(decoded.size == cast(u64) info.frames * #sizeof(s16) and nonZero > 8)
}

// Packet framing accepts both byte orders of the 14- and 16-bit representations and rejects a
// truncated header.
#test
{
    let bytes = expect File.readAllBytes(audioGetTestDataPath("dts-5.1-48000.dts").toString())
    let info  = expect Dts.frameInfo(bytes.toSlice())
    @assert(info.frameBytes == 2012 and info.frames == 512)

    var bigEndian: Array'u8
    bigEndian.add(bytes.toSlice()[0 until info.frameBytes])
    var index = 0'u64
    while index < bigEndian.count
    {
        let first = bigEndian[index]
        bigEndian[index]     = bigEndian[index + 1]
        bigEndian[index + 1] = first
        index                += 2
    }

    let swapped = expect Dts.frameInfo(bigEndian.toSlice())
    @assert(swapped.frameBytes == info.frameBytes and swapped.speakerMask == info.speakerMask)

    let packedBytes = expect File.readAllBytes(audioGetTestDataPath("dts-5.1-48000-14be.dts").toString())
    let packedInfo  = expect Dts.frameInfo(packedBytes.toSlice())
    @assert(packedInfo.frameBytes == 2300 and packedInfo.frames == info.frames)
    var littleEndian14: Array'u8
    littleEndian14.add(packedBytes.toSlice()[0 until packedInfo.frameBytes])
    index = 0
    while index < littleEndian14.count
    {
        let first = littleEndian14[index]
        littleEndian14[index]     = littleEndian14[index + 1]
        littleEndian14[index + 1] = first
        index                     += 2
    }

    let swapped14 = expect Dts.frameInfo(littleEndian14.toSlice())
    @assert(swapped14.frameBytes == packedInfo.frameBytes and swapped14.speakerMask == packedInfo.speakerMask)

    var malformed = catch Dts.frameInfo(bytes.toSlice()[0 until 8]) as err
    discard malformed
    @assert(err != null)
}
