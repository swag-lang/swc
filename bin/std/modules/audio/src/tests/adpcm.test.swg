#global if #command == Swag.CompilerCommand.Test

using Core, Core.Errors

// Decodes a sound to interleaved PCM16 through the device-independent path.
private func adpcmDecodeAll(sound: const *SoundFile)->Array's16 fail
{
    var result: retval
    try sound.decodePcm16(func|result = &result|(samples: const [..] s16)->bool
    {
        result.add(samples)
        return true
    })

    return result
}

// ADPCM is integer arithmetic with no rounding freedom, so the only acceptable result is the
// exact stream FFmpeg decodes from the same file, block padding included.
private func adpcmAssertExact(name: string, encoding: SoundFileEncoding, sampleRate, channels: u32, blockFrames: u32)
{
    let path  = audioGetTestDataPath(Format.toString("%.wav", name).toString())
    var sound = expect SoundFile.load(path.toString())
    @assert(sound.sampleEncoding() == encoding)
    @assert(sound.sampleRateHz() == sampleRate and sound.numChannels() == channels)
    @assert(sound.isPacketStream() and !sound.isDataPreloaded())
    @assert((expect sound.packet(0)).byteSize == 1024 and (expect sound.packet(0)).sampleFrameCount == blockFrames)

    let decoded = expect adpcmDecodeAll(&sound)
    let wanted  = expect File.readAllBytes(audioGetTestDataPath(Format.toString("%.pcm", name).toString()).toString())
    @assert(decoded.count == sound.sampleFrameCount() * channels)
    @assert(decoded.count * #sizeof(s16) == wanted.count)

    let wantedAt   = cast(const [*] s16) wanted.buffer!
    var mismatches = 0'u64
    for index in decoded.count where decoded[index] != wantedAt[index] do
        mismatches += 1
    if mismatches do
        @print("adpcm ", name, ": ", mismatches, " of ", decoded.count, " samples differ\n")
    @assert(mismatches == 0)
}

// Microsoft ADPCM, stereo: every byte carries one nibble for each channel.
#test
{
    adpcmAssertExact("adpcm-ms-stereo-22050", .AdpcmMs, 22_050, 2, 1012)
}

// Microsoft ADPCM, mono: every byte carries two consecutive samples.
#test
{
    adpcmAssertExact("adpcm-ms-mono-8000", .AdpcmMs, 8_000, 1, 2036)
}

// IMA ADPCM, stereo: nibbles come in four-byte groups that alternate between the channels.
#test
{
    adpcmAssertExact("adpcm-ima-stereo-44100", .AdpcmIma, 44_100, 2, 1017)
}

// IMA ADPCM, mono.
#test
{
    adpcmAssertExact("adpcm-ima-mono-11025", .AdpcmIma, 11_025, 1, 2041)
}

// A voice seeks to the block holding the target frame and discards the frames before it, so the
// samples heard after a seek are the same ones a decode from the start reaches.
#test
{
    destroyEngine()
    discard expect createNoSoundEngine()
    defer destroyEngine()

    var sound = expect SoundFile.load(audioGetTestDataPath("adpcm-ms-stereo-22050.wav").toString())
    let wanted = expect adpcmDecodeAll(&sound)
    let voice  = (expect Voice.create(&sound))!
    defer voice.destroy()

    const Target = 1500'u64
    expect voice.seekSampleFrame(Target)
    let decoded = expect voice.readBuffer()
    @assert(decoded.buffer != null and decoded.size >= 512 * 2 * #sizeof(s16))
    let samples = cast(const [*] s16) decoded.buffer!
    for index in 512 * 2 do
        @assert(samples[index] == wanted[Target * 2 + index])
}

// A `fmt ` chunk that declares ADPCM without a block alignment cannot be indexed.
#test
{
    discard catch SoundFile.load(audioGetTestDataPath("malformed_adpcm.wav")) as err
    @assert(err is Errors.InvalidFormatError)
}
