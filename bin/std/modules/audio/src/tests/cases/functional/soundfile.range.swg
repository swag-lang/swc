#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Explicit speaker masks contain one supported WAVE position for every channel.
#test
{
    const Config: [2] u8 = [0x11, 0x90]
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("speaker-mask-%.bin", Guid128.random()))
    defer discard catch File.delete(path)
    expect File.writeAllBytes(path, [0x00'u8])

    var packets: Array'SoundPacket
    packets.add({0, 1, 1})
    for mask in [0x0003'u32, 0x0004_0000'u32]
    {
        var outcome: Swag.Error
        discard catch SoundFile.openPacketStream(path, .AacLc, 48_000, 1, 1,
                                                 packets.toSlice(), Config,
                                                 PacketStreamOptions{speakerMask: mask}) as outcome
        Swag.require(outcome.value() is Errors.BadParameterError)
    }
}

// A compressed packet index may not expose bytes past the backing source file.
#test
{
    const Config: [2] u8 = [0x11, 0x90]
    const Packet: [1] SoundPacket = [SoundPacket{51, 2, 1}]
    let path = audioGetTestDataPath("pcm16_stereo.wav")

    var outcome: Swag.Error
    discard catch SoundFile.openPacketStream(path, .AacLc, 48_000, 1, 1, Packet, Config) as outcome
    Swag.require(outcome.value() is Errors.InvalidFormatError)
}

// A voice that has played the last frame of a long packet stream stands exactly at its duration,
// once its position is rounded to single precision like the duration. Past 2^24 frames, a
// duration divided in single precision lands a step beyond, where no position ever reaches.
#test
{
    const Frames = 16_779_519'u64
    Swag.require(cast(f32, Frames) / 44_100'f32 > cast(f32, cast(f64, Frames) / 44_100))

    let silence: [1] SoundPacket = [SoundPacket{0, 0, cast(u32, Frames)}]
    var config:  Array'u8
    var sound = expect SoundFile.openPacketStream(audioGetTestDataPath("pcm16_stereo.wav"), .Mp3, 44_100, 1, Frames, silence, config.toSlice())

    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = expect Voice.create(&sound)
    defer voice.destroy()
    discard expect voice.seekSampleFrame(Frames)
    Swag.require(voice.playbackSampleFrame() == sound.sampleFrameCount())
    Swag.require(cast(f32, voice.playbackPositionSeconds()) == sound.durationInSeconds())
}

// PCM ranges address audible frames, preserve interleaving and do not call back for an empty span.
#test
{
    let sound = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    var whole, selected: Array's16
    expect sound.decodePcm16(func|&whole|(part: const [..] s16)->bool
    {
        whole.add(part)
        return true
    })
    let count = sound.sampleFrameCount() - 1
    expect sound.decodePcm16(1, count, func|&selected|(part: const [..] s16)->bool
    {
        selected.add(part)
        return true
    })
    let begin = cast(u64, sound.numChannels())
    Swag.require(selected.count == count * sound.numChannels())
    Swag.require(Slice.equals(selected.toSlice(), whole.toSlice()[begin until begin + selected.count]))
    var calls: u32
    expect sound.decodePcm16(sound.sampleFrameCount(), 0, func|&calls|(_)->bool
    {
        calls += 1
        return true
    })
    Swag.require(calls == 0)
    var failure: Swag.Error
    catch sound.decodePcm16(sound.sampleFrameCount(), 1, func(_)->bool => true) as failure
    Swag.require(failure.value() is Errors.BadParameterError)
}

// A tail range must not decode a corrupt distant prefix. One AAC preroll packet reproduces
// uninterrupted PCM exactly, including a non-packet-aligned start and end.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("aac-range-%.bin", Guid128.random()))
    defer discard catch File.delete(path)
    var encoder = expect Aac.StreamEncoder.create(48_000, 1)
    var bytes, packet: Array'u8
    var packets:       Array'SoundPacket
    var signal:        [1_024] s16
    for sample in signal.count do
        signal[sample] = cast(s16, Math.round(6_000.0 * Math.sin(Math.ConstF64.TwoPi * 16 * sample / 1024)))
    for 16
    {
        discard expect encoder.push(signal, &packet)
        packets.add({bytes.count, cast(u32, packet.count), 1_024})
        bytes.add(packet.toSlice())
    }

    while expect encoder.finish(&packet)
    {
        packets.add({bytes.count, cast(u32, packet.count), 1_024})
        bytes.add(packet.toSlice())
    }

    discard expect File.writeAllBytes(path, bytes.toSlice())
    let sound = expect SoundFile.openPacketStream(path, .AacLc, 48_000, 1, packets.count * 1_024, packets.toSlice(), encoder.decoderConfig(), PacketStreamOptions{leadingTrimFrames: 1_024})
    var whole, selected: Array's16
    expect sound.decodePcm16(func|&whole|(part: const [..] s16)->bool
    {
        whole.add(part)
        return true
    })
    for index in packets[0].byteSize do
        bytes[index] = 0xFF
    discard expect File.writeAllBytes(path, bytes.toSlice())
    expect sound.decodePcm16(12_345, 2_345, func|&selected|(part: const [..] s16)->bool
    {
        selected.add(part)
        return true
    })
    Swag.require(selected.count == 2_345)
    Swag.require(Slice.equals(selected.toSlice(), whole.toSlice()[12_345 until 14_690]))

    let decodedStart   = 1_024'u64 + 12_345
    let decodedEnd     = decodedStart + 2_345
    var packetStart    = 0'u64
    var touchedPackets = 0'u32
    for index in sound.packetCount()
    {
        let packet    = expect sound.packet(index)
        let packetEnd = packetStart + packet.sampleFrameCount
        if packetStart < decodedEnd and packetEnd > decodedStart do
            touchedPackets += 1
        packetStart = packetEnd
    }

    Swag.require(touchedPackets > 1)

    var cancellationCalls = 0'u32
    expect sound.decodePcm16(12_345, 2_345, func|&cancellationCalls|(_: const [..] s16)->bool
    {
        cancellationCalls += 1
        return false
    })
    Swag.require(cancellationCalls == 1)

    var failure: Swag.Error
    catch sound.decodePcm16(0, 100, func(_)->bool => true) as failure
    Swag.require(failure.value() != null)
}
