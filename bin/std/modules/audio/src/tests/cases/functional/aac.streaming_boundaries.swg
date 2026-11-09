#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Encodes one stereo stream with an arbitrary maximum caller chunk and records packet boundaries.
func encodeStereoChunks(samples: const [..] s16, chunkFrames: u64)->Array'u8 fail
{
    var encoder = try Aac.StreamEncoder.create(48_000, 2)
    var output: Array'u8
    var packet: Array'u8
    var cursor = 0'u64
    var packetIndex = 0'u64
    let frames = samples.count / 2
    while cursor < frames
    {
        let offered = Math.min(chunkFrames, frames - cursor)
        let consumed = try encoder.push(samples[cursor * 2 until (cursor + offered) * 2], &packet)
        Swag.require(consumed > 0 and consumed <= offered)
        cursor += consumed
        if packet.count
        {
            Swag.require(encoder.lastPacketStartSample() == packetIndex * 1_024 and
                         encoder.lastPacketValidFrames() == 1_024)
            output.add(cast(u8, packet.count & 255))
            output.add(cast(u8, packet.count >> 8))
            output.add(packet.toSlice())
            packetIndex += 1
        }
    }
    while try encoder.finish(&packet)
    {
        let expectedValid = packetIndex * 1_024 < frames ?
                            cast(u32, frames - packetIndex * 1_024) : 0'u32
        Swag.require(encoder.lastPacketStartSample() == packetIndex * 1_024 and
                     encoder.lastPacketValidFrames() == expectedValid)
        output.add(cast(u8, packet.count & 255))
        output.add(cast(u8, packet.count >> 8))
        output.add(packet.toSlice())
        packetIndex += 1
    }
    Swag.require(encoder.inputFrameCount() == frames and
                 encoder.packetCount() == (frames + 1_023) / 1_024 + 1 and
                 not (try encoder.finish(&packet)) and packet.isEmpty())
    return output
}

// Boundaries on both sides of 1024 and 2048 frames preserve output bytes and final valid frames.
#test
{
    var source: [4_097 * 2] s16
    for index in source.count do
        source[index] = cast(s16, cast(s32, index * 37 % 30_000) - 15_000)
    for frames in [1'u64, 1_023, 1_024, 1_025, 2_048, 2_049, 4_097]
    {
        let samples = Swag.makeSlice(&source[0], frames * 2)
        let whole = expect encodeStereoChunks(samples, frames)
        let single = expect encodeStereoChunks(samples, 1)
        let uneven = expect encodeStereoChunks(samples, 1_037)
        Swag.require(Slice.equals(whole.toSlice(), single.toSlice()) and
                     Slice.equals(whole.toSlice(), uneven.toSlice()))
    }
}

// A single nonzero frame after a complete block remains in the audible, left-only tail.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("aac-last-sample-%.aac", Guid128.random()))
    defer discard catch File.delete(path)
    var source: [1_025 * 2] s16
    source[1_024 * 2] = 20_000
    var encoder = expect Aac.StreamEncoder.create(48_000, 2)
    var encoded: Array'u8
    var packets: Array'SoundPacket
    var packet: Array'u8
    var cursor = 0'u64
    while cursor < 1_025
    {
        let offered = Math.min(37'u64, 1_025'u64 - cursor)
        cursor += expect encoder.push(Swag.makeSlice(&source[cursor * 2], offered * 2), &packet)
        if packet.count
        {
            packets.add({encoded.count, cast(u32, packet.count), 1_024})
            encoded.add(packet.toSlice())
        }
    }
    while expect encoder.finish(&packet)
    {
        packets.add({encoded.count, cast(u32, packet.count), 1_024})
        encoded.add(packet.toSlice())
    }
    Swag.require(packets.count == 3 and encoder.inputFrameCount() == 1_025)
    discard expect File.writeAllBytes(path.toString(), encoded.toSlice())
    let sound = expect SoundFile.openPacketStream(path.toString(), .AacLc, 48_000, 2,
                                                  packets.count * 1_024, packets.toSlice(),
                                                  encoder.decoderConfig())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == 3 * 1_024 * 2)
    var leftPeak = 0's32
    var rightPeak = 0's32
    var peakAt = 0'u64
    for frame in 1_900 until 2_200
    {
        let left = Math.abs(cast(s32, decoded[frame * 2]))
        let right = Math.abs(cast(s32, decoded[frame * 2 + 1]))
        if left > leftPeak
        {
            leftPeak = left
            peakAt = frame
        }
        rightPeak = Math.max(rightPeak, right)
    }
    Swag.require(leftPeak > 1_000 and Math.abs(cast(s64, peakAt) - 2_048) < 64 and
                 rightPeak < 100)
}
