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

    var result: retval
    var block:  Array'u8
    block.resize(MaxBlockSize * cast(u64) sound.numChannels() * #sizeof(s16))
    for index in sound.packetCount()
    {
        let packet   = try sound.packet(index)
        let produced = try itf.decodePacket(block.buffer!, block.count, bytes[packet.sourceOffset until packet.sourceOffset + packet.byteSize])
        result.add(block.toSlice()[0 until produced])
    }

    return result
}

// FLAC is lossless, so the only acceptable result is the exact stream that was encoded.
//
// The reference is the interleaved 16-bit PCM the fixture was produced from, not this module's own
// output, so a decoder that is merely self-consistent cannot pass.
private func flacAssertLossless(name: string, sampleRate, channels: u32)
{
    let path  = audioGetTestDataPath(Format.toString("%.flac", name).toString())
    var sound = expect SoundFile.load(path.toString())
    Swag.assert(sound.sampleEncoding() == .Flac)
    Swag.assert(sound.sampleRateHz() == sampleRate and sound.numChannels() == channels)

    let decoded = expect flacDecodeAll(&sound)
    let wanted  = expect File.readAllBytes(audioGetTestDataPath(Format.toString("%.pcm", name).toString()).toString())
    Swag.assert(sound.sampleFrameCount() * cast(u64) channels * #sizeof(s16) == wanted.count)
    Swag.assert(decoded.count == wanted.count)

    var mismatches = 0'u64
    for index in decoded.count where decoded[index] != wanted[index] do
        mismatches += 1
    if mismatches do
        Swag.print("flac ", name, ": ", mismatches, " of ", decoded.count, " bytes differ\n")
    Swag.assert(mismatches == 0)
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

// Opening a file walks its frame headers rather than its audio, and the index it builds agrees
// with the length the stream information states.
#test
{
    var sound = expect SoundFile.load(audioGetTestDataPath("flac-5.1-48000.flac").toString())
    Swag.assert(sound.isPacketStream() and !sound.isDataPreloaded())
    Swag.assert(sound.packetCount() == 6)
    Swag.assert((expect sound.packet(0)).sampleFrameCount == 4608)
    Swag.assert(sound.sampleFrameCount() == 24_000)
    Swag.assert(sound.speakerChannelMask() == 0x3F)
}

// A file that carries the marker and nothing else fails on its own terms rather than being
// decoded into noise.
#test
{
    let directory = Env.getSpecialDirectory(.Temp)
    let path      = Path.combine(directory.toString(), Format.toString("audio-flac-%.flac", Guid64.random()).toString())
    defer discard catch File.delete(path.toString())

    var bytes: Array'u8
    bytes.add("fLaC")
    expect File.writeAllBytes(path.toString(), bytes.toSlice())
    var sound = catch SoundFile.load(path.toString()) as err
    discard sound
    Swag.assert(err != null)
}

// The codec is reachable through the registry a container uses, and what a voice plays back is
// the start of the same reference stream.
#test
{
    var sound = expect SoundFile.load(audioGetTestDataPath("flac-5.1-48000.flac").toString())

    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = (expect Voice.create(&sound))!
    defer voice.destroy()
    let decoded = expect voice.readBuffer()
    Swag.assert(decoded.size != 0)

    let wanted = expect File.readAllBytes(audioGetTestDataPath("flac-5.1-48000.pcm").toString())
    let bytes  = cast(const [*] u8) decoded.buffer!
    let count  = Math.min(cast(u64) decoded.size, wanted.count)
    for index in count do
        Swag.assert(bytes[index] == wanted[index])
}
