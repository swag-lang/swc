#global if #command == Swag.CompilerCommand.Test

using Core, Core.Errors

// Decodes a sound to interleaved PCM16 through the device-independent path.
private func vorbisDecodeAll(sound: const *SoundFile)->Array's16 fail
{
    var result: retval
    try sound.decodePcm16(func|result = &result|(samples: const [..] s16)->bool
    {
        result.add(samples)
        return true
    })

    return result
}

// Compares a decode against libvorbis's, the reference implementation of the format. Two correct
// decoders differ in the last bit of their floating-point paths, while a defect produces a burst,
// so the measure is the root mean square of the difference across the whole stream, against the
// full scale, with a threshold a few last bits wide.
private func vorbisAssertCloseTo(name: string, sampleRate, channels: u32)
{
    var sound = expect SoundFile.load(audioGetTestDataPath(Format.toString("%.ogg", name).toString()).toString())
    @assert(sound.sampleEncoding() == .Vorbis)
    @assert(sound.sampleRateHz() == sampleRate and sound.numChannels() == channels)
    @assert(sound.isPacketStream() and !sound.isDataPreloaded())

    let decoded = expect vorbisDecodeAll(&sound)
    let wanted  = expect File.readAllBytes(audioGetTestDataPath(Format.toString("%.pcm", name).toString()).toString())
    @assert(decoded.count == sound.sampleFrameCount() * channels)
    @assert(decoded.count * #sizeof(s16) == wanted.count)

    let wantedAt = cast(const [*] s16) wanted.buffer!
    var energy   = 0.0'f64
    var worst    = 0.0'f64
    for index in decoded.count
    {
        let difference = cast(f64) decoded[index] - cast(f64) wantedAt[index]
        energy += difference * difference
        worst  = Math.max(worst, Math.abs(difference))
    }

    let rms = Math.sqrt(energy / cast(f64) decoded.count) / 32768.0'f64
    if rms > 0.0001'f64 do
        @print("vorbis ", name, ": rms ", rms, " over ", decoded.count, " samples, worst ", worst, "\n")
    @assert(rms <= 0.0001'f64)
}

// Stereo tones at 44.1 kHz: floor 1, residue 2 with coupling, and long blocks throughout.
#test
{
    vorbisAssertCloseTo("vorbis-stereo-44100", 44_100, 2)
}

// Clicks over noise, which make the encoder switch between long and short blocks and exercise
// every window shape.
#test
{
    vorbisAssertCloseTo("vorbis-transient-44100", 44_100, 2)
}

// The reader indexes runs of pages and states the samples each one completes; the last page's
// granule position trims the stream to the length the encoder was given.
#test
{
    var sound = expect SoundFile.load(audioGetTestDataPath("vorbis-stereo-44100.ogg").toString())
    @assert(sound.packetCount() == 2)
    @assert((expect sound.packet(0)).sampleFrameCount == 44_032)
    @assert(sound.sampleFrameCount() == 44_160)
    @assert(sound.speakerChannelMask() == 0x0003)
    @assert(sound.leadingTrim == 0)
}

// A voice restarts on the run before the target and discards up to it, so the samples heard after
// a seek are the ones a decode from the start reaches at that position.
#test
{
    destroyEngine()
    discard expect createNoSoundEngine()
    defer destroyEngine()

    var sound  = expect SoundFile.load(audioGetTestDataPath("vorbis-transient-44100.ogg").toString())
    let wanted = expect vorbisDecodeAll(&sound)
    let voice  = (expect Voice.create(&sound))!
    defer voice.destroy()

    const Target = 44_100'u64
    expect voice.seekSampleFrame(Target)
    let decoded = expect voice.readBuffer()
    @assert(decoded.buffer != null and decoded.size >= 32 * 2 * #sizeof(s16))
    let samples = cast(const [*] s16) decoded.buffer!
    for index in 32 * 2 do
        @assert(samples[index] == wanted[Target * 2 + index])
}

// A file that is not Ogg fails on its own terms rather than being decoded into noise.
#test
{
    let directory = Env.getSpecialDirectory(.Temp)
    let path      = Path.combine(directory.toString(), Format.toString("audio-ogg-%.ogg", Guid64.random()).toString())
    defer discard catch File.delete(path.toString())

    var bytes: Array'u8
    bytes.add("not an ogg stream, not even close")
    expect File.writeAllBytes(path.toString(), bytes.toSlice())
    var sound = catch SoundFile.load(path.toString()) as err
    discard sound
    @assert(err is Errors.InvalidFormatError)
}
