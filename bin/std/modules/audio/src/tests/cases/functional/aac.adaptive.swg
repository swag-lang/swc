#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

struct AdaptiveOutput
{
    encoded: Array!{u8}
    packets: Array!{SoundPacket}
    windows: [4] u32
}

func encodeAdaptive(samples: const [..] s16, chunk: u64)->AdaptiveOutput fail
{
    var encoder = try Aac.StreamEncoder.createAdaptive(48_000, 1)
    Swag.require(encoder.encoderDelayFrames() == 1_024)
    var result: AdaptiveOutput
    var packet: Array!{u8}

    func append(encoder: const *Aac.StreamEncoder, packet: const *Array!{u8}, result: *AdaptiveOutput, frames: u64)
    {
        let start = result.packets.count * 1_024
        let valid = Math.min(1_024_u64, frames - Math.min(start, frames))
        Swag.require(encoder.lastPacketStartSample() == start and encoder.lastPacketValidFrames() == valid)
        Swag.require(packet.count >= 3)
        let sequence = (packet[2] >> 6) & 3
        result.windows[sequence] += 1
        result.packets.add({result.encoded.count, cast(u32, packet.count), 1_024})
        result.encoded.add(packet.toSlice())
    }

    var cursor = 0_u64
    while cursor < samples.count
    {
        let requested = Math.min(chunk, samples.count - cursor)
        let consumed  = try encoder.push(samples[cursor until cursor + requested], &packet)
        Swag.require(consumed > 0 and consumed <= requested)
        cursor += consumed
        if cursor <= 1_024
        {
            Swag.require(packet.isEmpty())
        }

        if packet.count
        {
            append(&encoder, &packet, &result, samples.count)
        }
    }

    while try encoder.finish(&packet)
    {
        append(&encoder, &packet, &result, samples.count)
    }

    let count = samples.count ? (samples.count + 1_023) / 1_024 + 1 : 0
    Swag.require(encoder.inputFrameCount() == samples.count and
                 result.packets.count == count and
                 encoder.packetCount() == count and
                 not (try encoder.finish(&packet)) and
                 packet.isEmpty())
    return result
}

#test
{
    const Frames = 12 * 1_024 + 193
    const First  = 4 * 1_024 + 64
    const Second = 8 * 1_024 + 832
    const Last   = Frames - 1
    var samples: [Frames] s16
    samples[First]  = 20_000
    samples[Second] = -20_000
    samples[Last]   = 20_000

    let input   = Swag.makeSlice(&samples[0], samples.count)
    let whole   = expect encodeAdaptive(input, 1_024)
    let chopped = expect encodeAdaptive(input, 83)
    Swag.require(Slice.equals(whole.encoded.toSlice(), chopped.encoded.toSlice()))
    Swag.require(whole.windows[1] and whole.windows[2] and whole.windows[3])

    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("aac-adaptive-%.aac", Guid128.random()))
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path.toString(), whole.encoded.toSlice())
    var config = expect Aac.StreamEncoder.createAdaptive(48_000, 1)
    let sound  = expect SoundFile.openPacketStream(path.toString(),
                                                   .AacLc,
                                                   48_000,
                                                   1,
                                                   whole.packets.count * 1_024,
                                                   whole.packets.toSlice(),
                                                   config.decoderConfig())
    var decoded: Array!{s16}
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == whole.packets.count * 1_024)
    for impulse in [First, Second, Last]
    {
        let position = cast(u64, impulse) + 1_024
        let peak     = cast(s32, decoded[position])
        Swag.require(Math.abs(peak) >= 19_000)
        for offset in position - 768 until position - 256
        {
            Swag.require(decoded[offset] == 0)
        }

        for offset in position - 64 until position + 64 where offset != position
        {
            Swag.require(Math.abs(cast(s32, decoded[offset])) < Math.abs(peak))
        }
    }
}

#test
{
    for length in [0_u64, 1, 1_023, 1_024, 1_025, 2_048]
    {
        var silence: [2_048] s16
        let samples = Swag.makeSlice(&silence[0], length)
        let whole   = expect encodeAdaptive(samples, 1_024)
        let chopped = expect encodeAdaptive(samples, 19)
        Swag.require(Slice.equals(whole.encoded.toSlice(), chopped.encoded.toSlice()))
        Swag.require(whole.windows[0] == whole.packets.count)
    }
}
