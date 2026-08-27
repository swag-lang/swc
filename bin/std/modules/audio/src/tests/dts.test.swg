#global if #command == Swag.CompilerCommand.Test

using Core

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

// A native DTS Core stream is indexed from its frame headers, decoded through the packet-codec
// registry, and exposed in WAVE FL,FR,FC,LFE,BL,BR speaker order.
#test
{
    let path  = audioGetTestDataPath("dts-5.1-48000.dts")
    var sound = expect SoundFile.load(path.toString())

    @assert(sound.sampleEncoding() == .Dts)
    @assert(sound.sampleRateHz() == 48_000 and sound.numChannels() == 6)
    @assert(sound.speakerChannelMask() == 0x3F)
    @assert(sound.packetCount() == 47 and sound.sampleFrameCount() == 47 * 512)
    let first = expect sound.packet(0)
    @assert(first.sourceOffset == 0 and first.byteSize == 2012 and first.sampleFrameCount == 512)

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

// Packet framing accepts both standard 16-bit byte orders and rejects a truncated header.
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

    var malformed = catch Dts.frameInfo(bytes.toSlice()[0 until 8]) as err
    discard malformed
    @assert(err != null)
}
