#global if #command == Swag.CompilerCommand.Test

using Core

private func aacTestPackets(path: string)->Array'SoundPacket fail
{
    let bytes  = try File.readAllBytes(path)
    var result: retval
    var offset = 0'u64
    while offset < bytes.count
    {
        if bytes.count - offset < 7 or bytes[offset] != 0xFF or bytes[offset + 1] & 0xF6 != 0xF0 do
            fail InvalidFormatError{"AAC test fixture has an invalid ADTS header"}
        let frameSize = (cast(u32) (bytes[offset + 3] & 3) << 11) | (cast(u32) bytes[offset + 4] << 3) | (cast(u32) bytes[offset + 5] >> 5)
        if frameSize < 7 or frameSize > bytes.count - offset do
            fail InvalidFormatError{"AAC test fixture has a truncated ADTS frame"}
        result.add({offset + 7, frameSize - 7, 1024})
        offset += frameSize
    }

    return result
}

private func aacTestSound()->SoundFile fail
{
    const Config: [2] u8 = [0x12, 0x10]
    let path    = audioGetTestDataPath("aac-lc-stereo-44100.aac")
    let packets = try aacTestPackets(path)
    return SoundFile.openPacketStream(path, .AacLc, 44_100, 2, packets.count * 1024, packets.toSlice(), Config)
}

private func aacTonePower(samples: const [*] s16, firstFrame, frameCount, channel: u64, frequency: f64)->f64
{
    var real, imaginary: f64
    for frame in frameCount
    {
        let angle = 2.0 * Math.ConstF64.Pi * frequency * cast(f64) frame / 44_100.0
        let value = cast(f64) samples[(firstFrame + frame) * 2 + channel]
        real      += value * Math.cos(angle)
        imaginary -= value * Math.sin(angle)
    }

    return real * real + imaginary * imaginary
}

#test
{
    var sound = expect aacTestSound()
    @assert(sound.sampleEncoding() == .AacLc)
    @assert(sound.sampleRateHz() == 44_100 and sound.numChannels() == 2)
    @assert(sound.packetCount() > 40 and !sound.isDataPreloaded())

    // Logical payload reads cross the ADTS headers between sparse access units instead of
    // treating their file offsets as a contiguous byte stream.
    let source = expect File.readAllBytes(audioGetTestDataPath("aac-lc-stereo-44100.aac"))
    let first  = expect sound.packet(0)
    let second = expect sound.packet(1)
    let joined = expect sound.readPayload(first.byteSize - 3, 6)
    @assert(joined[0] == source[first.sourceOffset + first.byteSize - 3])
    @assert(joined[2] == source[first.sourceOffset + first.byteSize - 1])
    @assert(joined[3] == source[second.sourceOffset])
    @assert(joined[5] == source[second.sourceOffset + 2])

    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice   = (expect Voice.create(&sound))!
    let decoded = expect voice.readBuffer()
    @assert(decoded.size == 4 * 1024 * 2 * #sizeof(s16))
    let samples = cast(const [*] s16) decoded.buffer!
    var peak    = 0's32
    for index in decoded.size / #sizeof(s16) do
        peak = Math.max(peak, Math.abs(cast(s32) samples[index]))
    @assert(peak > 1_000)
    @assert(aacTonePower(samples, 2_048, 2_048, 0, 440) > 10.0 * aacTonePower(samples, 2_048, 2_048, 0, 660))
    @assert(aacTonePower(samples, 2_048, 2_048, 1, 660) > 10.0 * aacTonePower(samples, 2_048, 2_048, 1, 440))

    discard expect voice.seekSampleFrame(5 * 1024 + 256)
    let afterSeek = expect voice.readBuffer()
    @assert(afterSeek.size == (4 * 1024 - 256) * 2 * #sizeof(s16))
    @assert(voice.streamPacketIdx == 9)
    voice.destroy()
}


#test
{
    var sound = expect aacTestSound()
    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = (expect Voice.create(&sound))!
    discard expect voice.play()
    discard expect voice.updateNoSound()
    @assert(voice.playbackSampleFrame() == sound.sampleFrameCount())
    @assert(!(cast(*NoSoundVoice) voice.handle!).isPlaying)
    voice.destroy()
}
