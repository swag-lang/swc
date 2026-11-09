#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Fourier amplitude in a steady 0.5-second window after the AAC priming packet.
func decodedToneAmplitude(samples: const [..] s16, channel: u64, frequency: f64)->f64
{
    var sine = 0.0'f64
    var cosine = 0.0'f64
    for frame in 1_024 + 12_000 until 1_024 + 36_000
    {
        let phase = Math.ConstF64.TwoPi * frequency * (frame - 1_024) / 48_000.0
        let sample = cast(f64, samples[frame * 2 + channel])
        sine += sample * Math.sin(phase)
        cosine += sample * Math.cos(phase)
    }
    return 2.0 * Math.sqrt(sine * sine + cosine * cosine) / 24_000.0
}

// A faint high tone must survive a much louder bass tone in the same stereo channel.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("aac-band-gain-%.aac", Guid128.random()))
    defer discard catch File.delete(path)
    var encoder = expect Aac.StreamEncoder.create(48_000, 2)
    var source: [48_000 * 2] s16
    for frame in 48_000
    {
        let time = frame / 48_000.0
        let faint = 160.0 * Math.sin(Math.ConstF64.TwoPi * 12_000.0 * time)
        source[frame * 2] = cast(s16, Math.round(24_000.0 *
            Math.sin(Math.ConstF64.TwoPi * 440.0 * time) + faint))
        source[frame * 2 + 1] = cast(s16, Math.round(faint))
    }
    var encoded: Array'u8
    var packets: Array'SoundPacket
    var packet: Array'u8
    var cursor = 0'u64
    while cursor < 48_000
    {
        let count = Math.min(1_024'u64, 48_000'u64 - cursor)
        cursor += expect encoder.push(Swag.makeSlice(&source[cursor * 2], count * 2), &packet)
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
    Swag.require(decoded.count == packets.count * 1_024 * 2)
    let bassLeft = decodedToneAmplitude(decoded.toSlice(), 0, 440.0)
    let bassRight = decodedToneAmplitude(decoded.toSlice(), 1, 440.0)
    let highLeft = decodedToneAmplitude(decoded.toSlice(), 0, 12_000.0)
    let highRight = decodedToneAmplitude(decoded.toSlice(), 1, 12_000.0)
    Swag.require(bassLeft > 22_000 and bassLeft < 26_000 and bassRight < 100)
    Swag.require(highLeft > 80 and highLeft < 240 and
                 highRight > 80 and highRight < 240)
}
