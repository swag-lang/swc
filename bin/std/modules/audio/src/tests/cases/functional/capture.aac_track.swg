#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

// A timestamp gap becomes exactly one silent AAC packet between two tones.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("audio-capture-aac-track-%.aac", Guid128.random()))
    defer discard catch File.delete(path)
    var queue = expect CaptureQueue.create(48_000, 1, 0, 48_000,
                                           blockFrames: 1_024, tolerance: 0)
    var tone: [1_024] s16
    for frame in tone.count do
        tone[frame] = cast(s16, Math.round(9_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                               1_000.0 * frame / 48_000.0)))
    discard expect queue.push(Swag.makeSlice(&tone[0], tone.count), 0)
    discard expect queue.push(Swag.makeSlice(&tone[0], tone.count), 2_048)
    var track = expect CaptureAacTrack.create(&queue)
    Swag.require(track.sampleRateHz() == 48_000 and track.encoderDelayFrames() == 1_024)
    var file: Array'u8
    var packets: Array'SoundPacket
    var packet: Array'u8
    var info: CaptureAacPacket
    var count = 0'u64
    while expect track.nextPacket(&packet, &info)
    {
        Swag.require(info.startSample == count * 1_024 and info.validFrames == 1_024)
        Swag.require(info.syntheticFrames == (count == 1 ? 1_024 : 0))
        packets.add({file.count, cast(u32, packet.count), 1_024})
        file.add(packet.toSlice())
        count += 1
    }
    Swag.require(count == 3 and track.inputFrameCount() == 3 * 1_024)
    while expect track.finish(&packet, &info)
    {
        Swag.require(info.startSample == count * 1_024 and info.validFrames == 0)
        packets.add({file.count, cast(u32, packet.count), 1_024})
        file.add(packet.toSlice())
        count += 1
    }
    Swag.require(count == 4)
    discard expect File.writeAllBytes(path.toString(), file.toSlice())
    let sound = expect SoundFile.openPacketStream(path.toString(), .AacLc, 48_000, 1,
                                                  count * 1_024, packets.toSlice(), track.decoderConfig())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == count * 1_024)
    var before = 0.0'f64
    var gap = 0.0'f64
    var after = 0.0'f64
    for frame in 1_024
    {
        before += cast(f64, decoded[1_024 + frame]) * decoded[1_024 + frame]
        gap += cast(f64, decoded[2_048 + frame]) * decoded[2_048 + frame]
        after += cast(f64, decoded[3_072 + frame]) * decoded[3_072 + frame]
    }
    Swag.require(Math.sqrt(before / 1_024) > 3_000)
    Swag.require(Math.sqrt(gap / 1_024) < 500)
    Swag.require(Math.sqrt(after / 1_024) > 3_000)
}

// A lost source emits silence while offline; its resumed PCM is marked on the packet.
#test
{
    var queue = expect CaptureQueue.create(48_000, 1, 0, 48_000,
                                           blockFrames: 1_024, tolerance: 0)
    var samples: [1_024] s16
    for frame in samples.count do
        samples[frame] = cast(s16, frame % 255)
    discard expect queue.push(Swag.makeSlice(&samples[0], samples.count), 0)
    expect queue.markLost(1_024)
    expect queue.markLost(4_096)
    var track = expect CaptureAacTrack.create(&queue, .Voice)
    var packet: Array'u8
    var info: CaptureAacPacket
    for index in 4
    {
        Swag.require(expect track.nextPacket(&packet, &info))
        Swag.require(info.startSample == index * 1_024)
        Swag.require(info.syntheticFrames == (index == 0 ? 0 : 1_024))
        Swag.require(not info.sourceInterrupted)
    }
    Swag.require(not expect track.nextPacket(&packet, &info) and packet.isEmpty())
    expect queue.markRestored(4_096)
    discard expect queue.push(Swag.makeSlice(&samples[0], samples.count), 4_096)
    Swag.require(expect track.nextPacket(&packet, &info))
    Swag.require(info.startSample == 4_096 and info.syntheticFrames == 0)
    Swag.require(info.sourceInterrupted and track.inputFrameCount() == 5 * 1_024)
    Swag.require(expect track.finish(&packet, &info))
    Swag.require(info.startSample == 5 * 1_024 and info.validFrames == 0)
    Swag.require(not expect track.finish(&packet, &info) and packet.isEmpty())
}

// Arbitrary queue block sizes preserve packet starts and final valid-frame counts.
#test
{
    var queue = expect CaptureQueue.create(44_100, 2, 0, 44_100,
                                           blockFrames: 2_048, tolerance: 0)
    var first: [300 * 2] s16
    var second: [1_000 * 2] s16
    var third: [2_000 * 2] s16
    discard expect queue.push(Swag.makeSlice(&first[0], first.count), 0)
    discard expect queue.push(Swag.makeSlice(&second[0], second.count), 300)
    discard expect queue.push(Swag.makeSlice(&third[0], third.count), 1_300)
    var track = expect CaptureAacTrack.create(&queue)
    var packet: Array'u8
    var info: CaptureAacPacket
    for index in 3
    {
        Swag.require(expect track.nextPacket(&packet, &info))
        Swag.require(info.startSample == index * 1_024 and info.validFrames == 1_024)
        Swag.require(info.syntheticFrames == 0)
    }
    Swag.require(not expect track.nextPacket(&packet, &info) and packet.isEmpty())
    Swag.require(track.inputFrameCount() == 3_300)
    Swag.require(expect track.finish(&packet, &info))
    Swag.require(info.startSample == 3 * 1_024 and info.validFrames == 228)
    Swag.require(expect track.finish(&packet, &info))
    Swag.require(info.startSample == 4 * 1_024 and info.validFrames == 0)
    Swag.require(not expect track.finish(&packet, &info))
}

// A queue overrun is encoded as silence without retaining a history of dropped blocks.
#test
{
    var queue = expect CaptureQueue.create(48_000, 1, 0, 48_000,
                                           blockFrames: 1_024, slots: 2, tolerance: 0)
    var block: [1_024] s16
    for index in 3
    {
        block[0] = cast(s16, index + 1)
        discard expect queue.push(Swag.makeSlice(&block[0], block.count), index * 1_024)
    }
    Swag.require(queue.droppedBlockCount() == 1)
    var track = expect CaptureAacTrack.create(&queue)
    var packet: Array'u8
    var info: CaptureAacPacket
    for index in 3
    {
        Swag.require(expect track.nextPacket(&packet, &info))
        Swag.require(info.startSample == index * 1_024)
        Swag.require(info.syntheticFrames == (index == 0 ? 1_024 : 0))
    }
    Swag.require(not expect track.nextPacket(&packet, &info))
}

// A partial hole and a resumed source can share one AAC packet without losing metadata.
#test
{
    var queue = expect CaptureQueue.create(48_000, 1, 0, 48_000,
                                           blockFrames: 1_024, tolerance: 0)
    var first: [500] s16
    var second: [1_000] s16
    first[0] = 5_000
    second[0] = 7_000
    discard expect queue.push(Swag.makeSlice(&first[0], first.count), 0)
    expect queue.markLost(500)
    expect queue.markRestored(600)
    discard expect queue.push(Swag.makeSlice(&second[0], second.count), 600)
    var track = expect CaptureAacTrack.create(&queue)
    var packet: Array'u8
    var info: CaptureAacPacket
    Swag.require(expect track.nextPacket(&packet, &info))
    Swag.require(info.startSample == 0 and info.validFrames == 1_024)
    Swag.require(info.syntheticFrames == 100 and info.sourceInterrupted)
    Swag.require(not expect track.nextPacket(&packet, &info))
    Swag.require(track.inputFrameCount() == 1_600)
    Swag.require(expect track.finish(&packet, &info))
    Swag.require(info.startSample == 1_024 and info.validFrames == 576)
    Swag.require(info.syntheticFrames == 0 and not info.sourceInterrupted)
}

// Invalid queue formats and post-finish reads fail without emitting a packet.
#test
{
    var unsupported = expect CaptureQueue.create(32_000, 1, 0, 32_000)
    var rejected: Swag.Error
    discard catch CaptureAacTrack.create(&unsupported) as rejected
    Swag.require(rejected.value() is BadParameterError)

    var queue = expect CaptureQueue.create(48_000, 1, 0, 48_000)
    var track = expect CaptureAacTrack.create(&queue)
    var packet: Array'u8
    var info: CaptureAacPacket
    info = CaptureAacPacket{startSample: 42, validFrames: 2, syntheticFrames: 1,
                            sourceInterrupted: true}
    packet.add(0xFF)
    Swag.require(not expect track.nextPacket(&packet, &info) and packet.isEmpty())
    Swag.require(info.startSample == 0 and info.validFrames == 0 and info.syntheticFrames == 0 and
                 not info.sourceInterrupted)

    info = CaptureAacPacket{startSample: 42, validFrames: 2, syntheticFrames: 1,
                            sourceInterrupted: true}
    packet.add(0xFF)
    Swag.require(not expect track.finish(&packet, &info) and packet.isEmpty())
    Swag.require(info.startSample == 0 and info.validFrames == 0 and info.syntheticFrames == 0 and
                 not info.sourceInterrupted)
    discard catch track.nextPacket(&packet, &info) as rejected
    Swag.require(rejected.value() is BadParameterError)
}
