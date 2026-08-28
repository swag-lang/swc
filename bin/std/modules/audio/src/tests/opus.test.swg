#global if #command == Swag.CompilerCommand.Test

using Core, Core.Errors

// Decodes a sound to interleaved PCM16 through the device-independent path.
private func opusDecodeAll(sound: const *SoundFile)->Array's16 fail
{
    var result: retval
    try sound.decodePcm16(func|result = &result|(samples: const [..] s16)->bool
    {
        result.add(samples)
        return true
    })

    return result
}

// Compares a decode against libopus's, the reference implementation of the format. The SILK layer
// is integer arithmetic and matches it exactly; the CELT layer is floating point, where two correct
// decoders differ in the last bits, so the measure is the root mean square of the difference across
// the whole stream, against the full scale.
private func opusAssertCloseTo(name: string, channels: u32, tolerance: f64)
{
    var sound = expect SoundFile.load(audioGetTestDataPath(Format.toString("%.opus", name).toString()).toString())
    @assert(sound.sampleEncoding() == .Opus)
    @assert(sound.sampleRateHz() == 48_000 and sound.numChannels() == channels)
    @assert(sound.isPacketStream() and !sound.isDataPreloaded())

    let decoded = expect opusDecodeAll(&sound)
    let wanted  = expect File.readAllBytes(audioGetTestDataPath(Format.toString("%.pcm", name).toString()).toString())
    @assert(decoded.count == sound.sampleFrameCount() * channels)
    @assert(decoded.count * #sizeof(s16) == wanted.count)

    let wantedAt = cast(const [*] s16) wanted.buffer!
    var energy   = 0.0'f64
    var worst    = 0.0'f64
    var worstAt  = 0'u64
    for index in decoded.count
    {
        let difference = cast(f64) decoded[index] - cast(f64) wantedAt[index]
        energy += difference * difference
        if Math.abs(difference) > worst
        {
            worst   = Math.abs(difference)
            worstAt = index
        }
    }

    let rms = Math.sqrt(energy / cast(f64) decoded.count) / 32768.0'f64
    if rms > tolerance do
        @print("opus ", name, ": rms ", rms, " over ", decoded.count, " samples, worst ", worst, " at ", worstAt, "\n")
    @assert(rms <= tolerance)
}

// Stereo tones in 20 ms CELT frames: the transform layer, its allocation, spreading, and stereo
// coding, at the fullband the music application selects.
#test
{
    opusAssertCloseTo("opus-stereo-48000", 2, 0.00001'f64)
}

// A mono tone at a voice bitrate: SILK alone, in its integer arithmetic, through the resampler.
#test
{
    opusAssertCloseTo("opus-mono-silk", 1, 0.0'f64)
}

// Stereo voice at a middle bitrate: hybrid frames, the mid/side coding of SILK, the CELT bands
// above it, and the switches to CELT and back with their redundant frames.
#test
{
    opusAssertCloseTo("opus-stereo-hybrid", 2, 0.00001'f64)
}

// Clicks over noise in 10 ms frames, which make the encoder use short blocks and transient
// shaping.
#test
{
    opusAssertCloseTo("opus-transient-48000", 2, 0.00001'f64)
}

// The reader indexes runs of pages, the header's pre-skip becomes the leading trim, and the last
// page's granule position sets the audible length.
#test
{
    var sound = expect SoundFile.load(audioGetTestDataPath("opus-stereo-48000.opus").toString())
    @assert(sound.sampleFrameCount() == 48_000)
    @assert(sound.leadingTrim == 312)
    @assert(sound.speakerChannelMask() == 0x0003)
    var total = 0'u64
    for index in sound.packetCount() do
        total += (expect sound.packet(index)).sampleFrameCount
    @assert(total == 48_000 + 312)
}

// A voice restarts on the run before the target and discards up to it, so the samples heard after
// a seek are the ones a decode from the start reaches at that position.
#test
{
    destroyEngine()
    discard expect createNoSoundEngine()
    defer destroyEngine()

    var sound  = expect SoundFile.load(audioGetTestDataPath("opus-transient-48000.opus").toString())
    let wanted = expect opusDecodeAll(&sound)
    let voice  = (expect Voice.create(&sound))!
    defer voice.destroy()

    const Target = 30_000'u64
    expect voice.seekSampleFrame(Target)
    let decoded = expect voice.readBuffer()
    @assert(decoded.buffer != null and decoded.size >= 32 * 2 * #sizeof(s16))
    let samples = cast(const [*] s16) decoded.buffer!
    for index in 32 * 2 do
        @assert(samples[index] == wanted[Target * 2 + index])
}

// A stream whose header announces a channel mapping the decoder does not implement fails on its
// own terms rather than being decoded into noise.
#test
{
    let directory = Env.getSpecialDirectory(.Temp)
    let path      = Path.combine(directory.toString(), Format.toString("audio-opus-%.opus", Guid64.random()).toString())
    defer discard catch File.delete(path.toString())

    var bytes = expect File.readAllBytes(audioGetTestDataPath("opus-mono-silk.opus").toString())
    // The mapping family lives at byte 18 of OpusHead, which the first page carries after its
    // 28-byte header; the page checksum must follow the change for the reader to reach it.
    @assert(bytes[28 + 18] == 0)
    bytes[28 + 18] = 1
    let firstPage = expect Ogg.readPageHeader(bytes.toSlice(), 0)
    let table     = Ogg.buildChecksumTable()
    let checksum  = Ogg.pageChecksum(bytes.toSlice()[0 until firstPage.totalBytes()], table)
    for i in 4 do
        bytes[22 + i] = cast(u8) ((checksum >> cast(u32) (8 * i)) & 0xFF)
    expect File.writeAllBytes(path.toString(), bytes.toSlice())
    var sound = catch SoundFile.load(path.toString()) as err
    discard sound
    @assert(err is Errors.UnsupportedFormatError)
}
