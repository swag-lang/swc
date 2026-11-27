#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

struct RateOutput
{
    encoded: Array!{u8}
    packets: Array!{SoundPacket}
}

func encodeRateLimited(samples: const [..] s16, chunk: u64)->RateOutput fail
{
    const Budget = 256_u64
    var encoder = try Aac.StreamEncoder.createRateLimited(48_000, 2, 96_000)
    Swag.require(encoder.encoderDelayFrames() == 1_024)
    var packet: Array!{u8}
    var result: RateOutput
    let frames     = samples.count / 2
    var consumed   = 0_u64
    var credit     = 0_u64
    var usedCredit = false

    let publish = func|&encoder, &packet, &result, &credit, &usedCredit, frames|()
    {
        let start = result.packets.count * 1_024
        let valid = Math.min(1_024_u64, frames - Math.min(start, frames))
        Swag.require(encoder.lastPacketStartSample() == start and encoder.lastPacketValidFrames() == valid)
        let available = Budget + credit
        Swag.require(packet.count > 0 and packet.count <= available)
        usedCredit = usedCredit or packet.count > Budget
        credit     = Math.min(3 * Budget, available - packet.count)
        result.packets.add({result.encoded.count, cast(u32, packet.count), 1_024})
        result.encoded.add(packet.toSlice())
        Swag.require(result.encoded.count <= result.packets.count * Budget)
    }

    while consumed < frames
    {
        let offered = Math.min(chunk, frames - consumed)
        let count   = try encoder.push(samples[2 * consumed until 2 * (consumed + offered)], &packet)
        Swag.require(count > 0 and count <= offered)
        consumed += count
        if packet.count
        {
            publish()
        }
    }

    while try encoder.finish(&packet)
    {
        publish()
    }

    Swag.require(usedCredit and encoder.inputFrameCount() == frames)
    Swag.require(encoder.packetCount() == (frames + 1_023) / 1_024 + 1)
    Swag.require(not (try encoder.finish(&packet)) and packet.isEmpty())
    return result
}

#test
{
    const Loud   = 3 * 1_024
    const Frames = 9 * 1_024 + 193
    var samples: [2 * Frames] s16
    var state = 0x1234_5678_u32
    for index in 2 * Loud until samples.count
    {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        samples[index] = cast(s16, cast(s32, state & 0xFFFF) - 32_768)
    }

    let input   = Swag.makeSlice(&samples[0], samples.count)
    let whole   = expect encodeRateLimited(input, 1_024)
    let chopped = expect encodeRateLimited(input, 79)
    Swag.require(Slice.equals(whole.encoded.toSlice(), chopped.encoded.toSlice()))

    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("aac-rate-%.aac", Guid128.random()))
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path.toString(), whole.encoded.toSlice())
    var config = expect Aac.StreamEncoder.createRateLimited(48_000, 2, 96_000)
    let sound  = expect SoundFile.openPacketStream(path.toString(),
                                                   .AacLc,
                                                   48_000,
                                                   2,
                                                   whole.packets.count * 1_024,
                                                   whole.packets.toSlice(),
                                                   config.decoderConfig())
    var decodedFrames = 0_u64
    var hasSignal     = false
    expect sound.decodePcm16(func|&decodedFrames, &hasSignal|(part: const [..] s16)->bool
    {
        decodedFrames += part.count / 2
        for sample in part where sample != 0
        {
            hasSignal = true
        }

        return true
    })
    Swag.require(decodedFrames == whole.packets.count * 1_024 and hasSignal)
}

#test
{
    var rejected: Swag.Error
    discard catch Aac.StreamEncoder.createRateLimited(48_000, 2, 4_000) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch Aac.StreamEncoder.createRateLimited(32_000, 2, 96_000) as rejected
    Swag.require(rejected.value() is BadParameterError)

    var encoder = expect Aac.StreamEncoder.createRateLimited(48_000, 2, 4_125)
    var packet: Array!{u8}
    packet.add(61_u8)
    const Odd = [17_s16]
    discard catch encoder.push(Swag.makeSlice(&Odd[0], Odd.count), &packet) as rejected
    Swag.require(rejected.value() is BadParameterError and encoder.inputFrameCount() == 0)
    Swag.require(packet.count == 1 and packet[0] == 61)
    Swag.require(not (expect encoder.finish(&packet)) and packet.isEmpty())
}

#test
{
    var encoder = expect Aac.StreamEncoder.createRateLimited(48_000, 2, 4_125)
    var samples: [2 * 1_024] s16
    for index in samples.count
    {
        samples[index] = index & 2 ? 32_767 : -32_768
    }

    var packet: Array!{u8}
    Swag.require((expect encoder.push(samples, &packet)) == 1_024)
    Swag.require(packet.count > 0 and packet.count <= 11)
    Swag.require(expect encoder.finish(&packet))
    Swag.require(packet.count > 0 and packet.count <= 11)
    Swag.require(not (expect encoder.finish(&packet)))
}
