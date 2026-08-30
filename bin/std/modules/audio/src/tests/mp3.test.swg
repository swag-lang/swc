#global if #command == Swag.CompilerCommand.Test

using Core, Core.Errors

// Decodes every packet of a loaded sound through the codec and returns interleaved PCM16.
//
// The packet table comes from the file reader, so this proves the two halves agree: a frame the
// index closed at the wrong byte does not decode.
private func mp3DecodeAll(sound: const *SoundFile)->Array's16 fail
{
    let file  = try File.readAllBytes(sound.sourcePath())
    let bytes = file.toSlice()

    var codec: Mp3.Codec
    let itf:   IPacketCodec = &codec
    try itf.initialize(sound.decoderConfig.toSlice(), sound.sampleRateHz(), sound.numChannels())

    var block: Array'u8
    block.resize(1152 * cast(u64) sound.numChannels() * #sizeof(s16))

    var result: retval
    for index in sound.packetCount()
    {
        let packet  = try sound.packet(index)
        let written = try itf.decodePacket(block.buffer!, block.count, bytes[packet.sourceOffset until packet.sourceOffset + packet.byteSize])
        let samples = cast(const [*] s16) block.buffer!
        for sample in written / #sizeof(s16) do
            result.add(samples[sample])
    }

    return result
}

// Device-independent decoding follows the same audible timeline as playback, including the MP3
// encoder delay that must be removed before frame zero reaches analysis consumers.
#test
{
    var sound = expect SoundFile.load(audioGetTestDataPath("mp3-stereo-44100.mp3").toString())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(samples: const [..] s16)->bool
    {
        decoded.add(samples)
        return true
    })

    Swag.assert(decoded.count == sound.sampleFrameCount() * sound.numChannels())
    var visible: bool
    for sample in decoded where Math.abs(cast(s32) sample) > 256
    {
        visible = true
        break
    }

    Swag.assert(visible)
}

// Packetized MP3 playback advances the same public cursor the player polls for its timeline.
#test
{
    destroyEngine()
    discard expect createNoSoundEngine()
    defer destroyEngine()

    var sound = expect SoundFile.load(audioGetTestDataPath("mp3-stereo-44100.mp3").toString())
    let voice = (expect Voice.create(&sound))!
    defer voice.destroy()
    discard expect voice.play(.Loop)
    discard expect voice.updateNoSound()
    Swag.assert(voice.playbackSampleFrame() > 0 and voice.playbackSampleFrame() < sound.sampleFrameCount())
}

// Compares a decode against FFmpeg's, the way the standard's own compliance criterion does.
//
// Layer III is lossy, so two correct decoders differ in the last bits; what a defect produces is
// not a rounding difference but a burst. The measure is therefore the root mean square of the
// difference across the whole stream, against the full scale of the format. The threshold is far
// tighter than the standard's, because two decoders of the same stream really do agree that well.
private func mp3AssertCloseTo(name: string, sampleRate, channels: u32)
{
    var sound = expect SoundFile.load(audioGetTestDataPath(Format.toString("%.mp3", name).toString()).toString())
    Swag.assert(sound.sampleEncoding() == .Mp3)
    Swag.assert(sound.sampleRateHz() == sampleRate and sound.numChannels() == channels)

    let decoded = expect mp3DecodeAll(&sound)
    let wanted  = expect File.readAllBytes(audioGetTestDataPath(Format.toString("%.pcm", name).toString()).toString())

    // The reader states the priming the encoder added; what a player hears starts after it.
    let skip     = sound.leadingTrim * cast(u64) channels
    let wantedAt = cast(const [*] s16) wanted.buffer!
    Swag.assert(decoded.count > skip)
    let count = Math.min(decoded.count - skip, wanted.count / #sizeof(s16))
    Swag.assert(count > cast(u64) sampleRate / 8)

    var energy = 0.0'f64
    var worst  = 0.0'f64
    for index in count
    {
        let difference = cast(f64) decoded[skip + index] - cast(f64) wantedAt[index]
        energy += difference * difference
        worst  = Math.max(worst, Math.abs(difference))
    }

    let rms = Math.sqrt(energy / cast(f64) count) / 32768.0'f64
    if rms > 0.001'f64 do
        Swag.print("mp3 ", name, ": rms ", rms, " over ", count, " samples, worst ", worst, "\n")
    Swag.assert(rms <= 0.001'f64)
}

// MPEG-1 Layer III, joint stereo, 44.1 kHz: the shape almost every music file has, with an ID3v2
// prologue, an encoder information frame, and a stated encoder delay.
#test
{
    mp3AssertCloseTo("mp3-stereo-44100", 44_100, 2)
}

// MPEG-2 Layer III at a low sampling frequency, mono, with no tag of any kind: 576 samples a
// frame, nine-bit scalefactor selection, and its own scalefactor band table.
#test
{
    mp3AssertCloseTo("mp3-mono-22050", 22_050, 1)
}

// Every sampling frequency of the three versions, because each one selects its own scalefactor
// band table and a wrong row is silent about itself.
#test
{
    mp3AssertCloseTo("mp3-mono-48000", 48_000, 1)
    mp3AssertCloseTo("mp3-mono-32000", 32_000, 1)
}

#test
{
    mp3AssertCloseTo("mp3-mono-24000", 24_000, 1)
    mp3AssertCloseTo("mp3-mono-16000", 16_000, 1)
}

// MPEG-2.5, which halves MPEG-2 again. Eight kilohertz has a band table of its own.
#test
{
    mp3AssertCloseTo("mp3-mono-12000", 12_000, 1)
    mp3AssertCloseTo("mp3-mono-11025", 11_025, 1)
    mp3AssertCloseTo("mp3-mono-8000", 8_000, 1)
}

// Clicks over noise at the highest bit rate: this is what makes an encoder switch to short and
// mixed blocks, and what fills the escape-coded Huffman tables with values above fifteen.
#test
{
    mp3AssertCloseTo("mp3-transient-44100", 44_100, 2)
}

// The reader states what the file says about itself rather than decoding to find out.
#test
{
    var tagged = expect SoundFile.load(audioGetTestDataPath("mp3-stereo-44100.mp3").toString())
    Swag.assert(tagged.isPacketStream() and !tagged.isDataPreloaded())
    Swag.assert((expect tagged.packet(0)).sampleFrameCount == 1152)
    Swag.assert(tagged.leadingTrim == 1105)
    Swag.assert(tagged.speakerChannelMask() == 0x0003)

    var bare = expect SoundFile.load(audioGetTestDataPath("mp3-mono-22050.mp3").toString())
    Swag.assert((expect bare.packet(0)).sampleFrameCount == 576)
    Swag.assert(bare.leadingTrim == 0)
}

// A file that is not one fails on its own terms rather than being decoded into noise.
#test
{
    let directory = Env.getSpecialDirectory(.Temp)
    let path      = Path.combine(directory.toString(), Format.toString("audio-mp3-%.mp3", Guid64.random()).toString())
    defer discard catch File.delete(path.toString())

    var bytes: Array'u8
    bytes.add("not an elementary stream")
    expect File.writeAllBytes(path.toString(), bytes.toSlice())
    var sound = catch SoundFile.load(path.toString()) as err
    discard sound
    Swag.assert(err != null)
}
