#global if #command == Swag.CompilerCommand.Test

using Core, Core.Errors

// Decodes every packet of a loaded sound through the codec alone and returns the interleaved
// samples.
//
// The packet table comes from the file reader, so this proves the two halves agree: a frame the
// index closed at the wrong byte does not decode.
private func flacDecodeAll(sound: const *SoundFile)->Array'u8 fail
{
    let file  = try File.readAllBytes(sound.sourcePath())
    let bytes = file.toSlice()

    var codec: Flac.Codec
    let itf:   IPacketCodec = &codec
    try itf.initialize(sound.decoderConfig.toSlice(), sound.sampleRateHz(), sound.numChannels())

    // The largest block a FLAC frame may carry, clause 8.
    const MaxBlockSize = 65_535'u64

    var result: #returntype
    var block:  Array'u8
    block.resize(MaxBlockSize * cast(u64, sound.numChannels()) * #sizeof(s16))
    for index in sound.packetCount()
    {
        let packet   = try sound.packet(index)
        let produced = try itf.decodePacket(block.storage(),
                                            block.count,
                                            bytes[packet.sourceOffset until packet.sourceOffset + packet.byteSize])
        result.add(block.toSlice()[0 until produced])
    }

    return result
}

private func flacTestHeaderCrc8(bytes: const [..] u8)->u8
{
    var crc = 0'u8
    for value in bytes
    {
        crc ^= value
        for 8 do
            crc = (crc & 0x80) != 0 ? cast(u8, ((crc << 1) ^ 0x07)) : cast(u8, (crc << 1))
    }
    return crc
}

private func flacTestAppendBits(bytes: *Array'u8, bitCount: *u64, value: u64, count: u32)
{
    for bit in count
    {
        if not (bitCount[] & 7) do
            bytes.add(0)
        let shift = count - 1 - bit
        if (value >> shift) & 1 do
            bytes[bitCount[] >> 3] |= cast(u8, 1'u32 << (7 - cast(u32, bitCount[] & 7)))
        bitCount[] += 1
    }
}

private func flacWideStereoTestConfig()->Array'u8
{
    var config: Array'u8
    config.add(0)
    config.add(1) // Min block size: one sample.
    config.add(0)
    config.add(1) // Max block size: one sample.
    for 6 do
        config.add(0) // Min/max frame sizes are unknown.
    let description = (48_000'u64 << 44) | (1'u64 << 41) | (31'u64 << 36) | 1
    for byte in 8 do
        config.add(cast(u8, (description >> (56 - byte * 8)) & 0xFF))
    for 16 do
        config.add(0) // MD5 is not consulted by the frame decoder.
    return config
}

private func flacWideMidSideFrame()->Array'u8
{
    var frame: Array'u8
    frame.add(0xFF)
    frame.add(0xF9) // Variable-block strategy.
    frame.add(0x60) // One-sample block size, sample rate from STREAMINFO.
    frame.add(0xA0) // Two-channel mid/side decorrelation, 32-bit samples from STREAMINFO.
    frame.add(0)    // Sample number.
    frame.add(0)    // Block size minus one.
    frame.add(flacTestHeaderCrc8(frame.toSlice()))

    var bitCount = frame.count * 8
    flacTestAppendBits(&frame, &bitCount, 0, 8)                  // Constant mid subframe.
    flacTestAppendBits(&frame, &bitCount, 0xFFFF_FFFF, 32)       // Mid = -1.
    flacTestAppendBits(&frame, &bitCount, 0, 8)                  // Constant side subframe.
    flacTestAppendBits(&frame, &bitCount, 0xFFFF_FFFF, 33)       // Side = 2^32 - 1.
    while bitCount & 7 do
        flacTestAppendBits(&frame, &bitCount, 0, 1)

    let checksum = Flac.frameCrc16(frame.toSlice())
    frame.add(cast(u8, checksum >> 8))
    frame.add(cast(u8, checksum & 0xFF))
    return frame
}

private func flacFrameWithInvalidSampleNumberPrefix()->Array'u8
{
    let valid = flacWideMidSideFrame()
    var frame: Array'u8
    for index in 5 do
        frame.add(valid[index])
    frame.add(0xFF)
    for 6 do
        frame.add(0x80)
    frame.add(valid[5]) // Block-size extension follows the seven-byte sample number.
    frame.add(flacTestHeaderCrc8(frame.toSlice()))
    frame.add(valid[7 until valid.count - 2])

    let checksum = Flac.frameCrc16(frame.toSlice())
    frame.add(cast(u8, checksum >> 8))
    frame.add(cast(u8, checksum & 0xFF))
    return frame
}

// FLAC is lossless, so the only acceptable result is the exact stream that was encoded.
//
// The reference is the interleaved 16-bit PCM the fixture was produced from, not this module's own
// output, so a decoder that is merely self-consistent cannot pass.
private func flacAssertLossless(name: string, sampleRate, channels: u32)
{
    let path  = audioGetTestDataPath(Format.toString("%.flac", name).toString())
    var sound = expect SoundFile.load(path.toString())
    Swag.require(sound.sampleEncoding() == .Flac)
    Swag.require(sound.sampleRateHz() == sampleRate and sound.numChannels() == channels)

    let decoded = expect flacDecodeAll(&sound)
    let wanted  = expect File.readAllBytes(audioGetTestDataPath(Format.toString("%.pcm", name).toString()).toString())
    Swag.require(sound.sampleFrameCount() * cast(u64, channels) * #sizeof(s16) == wanted.count)
    Swag.require(decoded.count == wanted.count)

    var mismatches = 0'u64
    for index in decoded.count where decoded[index] != wanted[index] do
        mismatches += 1
    if mismatches do
        Swag.print("flac ", name, ": ", mismatches, " of ", decoded.count, " bytes differ\n")
    Swag.require(mismatches == 0)
}

// Stereo, 44.1 kHz, sixteen bits: the shape a music file has.
#test
{
    flacAssertLossless("flac-stereo-44100", 44_100, 2)
}

// Six channels, 48 kHz: the shape a film track has, and the one whose channel order a container
// hands over unchanged.
#test
{
    flacAssertLossless("flac-5.1-48000", 48_000, 6)
}

// The side subframe of 32-bit mid/side stereo needs 33 bits to reconstruct the full PCM range.
#test
{
    var codec: Flac.Codec
    let decoder: IPacketCodec = &codec
    let config = flacWideStereoTestConfig()
    expect decoder.initialize(config.toSlice(), 48_000, 2)

    var decoded: [2] s16
    let frame = flacWideMidSideFrame()
    let bytes = expect decoder.decodePacket(cast([*] void, &decoded[0]), 2 * #sizeof(s16), frame.toSlice())
    Swag.require(bytes == 2 * #sizeof(s16))
    Swag.require(decoded[0] == Swag.S16.Max and decoded[1] == Swag.S16.Min)
}

// 0xFE is FLAC's seven-byte number prefix; 0xFF is reserved and rejected.
#test
{
    var codec: Flac.Codec
    let decoder: IPacketCodec = &codec
    let config = flacWideStereoTestConfig()
    expect decoder.initialize(config.toSlice(), 48_000, 2)

    var decoded: [2] s16
    let frame = flacFrameWithInvalidSampleNumberPrefix()
    var errorOutcome: Swag.Error
    discard catch decoder.decodePacket(cast([*] void, &decoded[0]), 2 * #sizeof(s16), frame.toSlice()) as errorOutcome
    Swag.require(errorOutcome.value() is InvalidFormatError)

    // The container index must reject the same invalid prefix before exposing a packet.
    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("audio-flac-invalid-number-%.flac", Guid64.random()).toString())
    defer discard catch File.delete(path.toString())
    var fileBytes: Array'u8
    fileBytes.add("fLaC")
    fileBytes.add(0x80) // Last metadata block: STREAMINFO.
    fileBytes.add(0)
    fileBytes.add(0)
    fileBytes.add(34)
    fileBytes.add(config.toSlice())
    fileBytes.add(frame.toSlice())
    expect File.writeAllBytes(path.toString(), fileBytes.toSlice())

    discard catch SoundFile.load(path.toString()) as errorOutcome
    Swag.require(errorOutcome.value() is InvalidFormatError)
}

// Opening a file walks its frame headers rather than its audio, and the index it builds agrees
// with the length the stream information states.
#test
{
    var sound = expect SoundFile.load(audioGetTestDataPath("flac-5.1-48000.flac").toString())
    Swag.require(sound.isPacketStream() and not sound.isDataPreloaded())
    Swag.require(sound.packetCount() == 6)
    Swag.require((expect sound.packet(0)).sampleFrameCount == 4608)
    Swag.require(sound.sampleFrameCount() == 24_000)
    Swag.require(sound.speakerChannelMask() == 0x3F)
}

// A file that carries the marker and nothing else fails on its own terms rather than being
// decoded into noise.
#test
{
    let directory = Env.getSpecialDirectory(.Temp)
    let path      = Path.combine(directory.toString(),
                                 Format.toString("audio-flac-%.flac", Guid64.random()).toString())
    defer discard catch File.delete(path.toString())

    var bytes: Array'u8
    bytes.add("fLaC")
    expect File.writeAllBytes(path.toString(), bytes.toSlice())
    var errOutcome: Swag.Error
    discard catch SoundFile.load(path.toString()) as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)
}

// The codec is reachable through the registry a container uses, and what a voice plays back is
// the start of the same reference stream.
#test
{
    var sound = expect SoundFile.load(audioGetTestDataPath("flac-5.1-48000.flac").toString())

    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = expect Voice.create(&sound)
    defer voice.destroy()
    let decoded = expect voice.readBuffer()
    Swag.require(decoded.size != 0)

    let wanted = expect File.readAllBytes(audioGetTestDataPath("flac-5.1-48000.pcm").toString())
    let bytes  = cast(const [*] u8, unwrap decoded.buffer)
    let count  = Math.min(cast(u64, decoded.size), wanted.count)
    for index in count do
        Swag.require(bytes[index] == wanted[index])
}
