#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

// Voice-band PCM becomes standard AAC-LC access units readable by the module's decoder.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("aac-software-%.aac", Guid128.random()))
    defer discard catch File.delete(path)
    var encoder = expect Aac.Encoder.create(48_000, 1)
    Swag.require(encoder.upperFrequencyHz() == 24_000)
    var file: Array'u8
    var packets: Array'SoundPacket
    var input: [10_240] s16
    for index in input.count do
        input[index] = cast(s16, Math.round(10_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                 1_000.0 * index / 48_000.0)))
    for block in 10
    {
        var encoded: Array'u8
        expect encoder.encode(Swag.makeSlice(&input[block * 1_024], 1_024), &encoded)
        Swag.require(encoded.count > 10 and encoded.count < 2_048)
        packets.add({file.count, cast(u32, encoded.count), encoder.packetFrames()})
        file.add(encoded.toSlice())
    }
    discard expect File.writeAllBytes(path.toString(), file.toSlice())
    let sound = expect SoundFile.openPacketStream(path.toString(), .AacLc, 48_000, 1,
                                                  input.count, packets.toSlice(), encoder.decoderConfig())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == input.count)
    var error = 0.0'f64
    var power = 0.0'f64
    var cross = 0.0'f64
    var decodedPower = 0.0'f64
    for index in 3_072 until 8_192
    {
        let original = cast(f64, input[index - 1_024])
        let actual = cast(f64, decoded[index])
        error += (original - actual) * (original - actual)
        power += original * original
        decodedPower += actual * actual
        cross += original * actual
    }
    Swag.require(Math.sqrt(error / power) < 0.15)
    Swag.require(cross / Math.sqrt(power * decodedPower) > 0.9)
    Swag.require(file.count < 1_500)
}

// Independent stereo channels preserve separate voice-band tones at 44.1 kHz.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("aac-software-stereo-%.aac", Guid128.random()))
    defer discard catch File.delete(path)
    var encoder = expect Aac.Encoder.create(44_100, 2)
    Swag.require(encoder.upperFrequencyHz() == 22_050)
    var file: Array'u8
    var packets: Array'SoundPacket
    var input: [12 * 1_024 * 2] s16
    for frame in 12 * 1_024
    {
        input[frame * 2] = cast(s16, Math.round(9_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                    1_000.0 * frame / 44_100.0)))
        input[frame * 2 + 1] = cast(s16, Math.round(7_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                        2_200.0 * frame / 44_100.0)))
    }
    for block in 12
    {
        var encoded: Array'u8
        expect encoder.encode(Swag.makeSlice(&input[block * 1_024 * 2], 1_024 * 2), &encoded)
        Swag.require(encoded.count > 10 and encoded.count < 2_048)
        packets.add({file.count, cast(u32, encoded.count), encoder.packetFrames()})
        file.add(encoded.toSlice())
    }
    discard expect File.writeAllBytes(path.toString(), file.toSlice())
    let sound = expect SoundFile.openPacketStream(path.toString(), .AacLc, 44_100, 2,
                                                  12 * 1_024, packets.toSlice(), encoder.decoderConfig())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == input.count)
    for channel in 2
    {
        var error = 0.0'f64
        var power = 0.0'f64
        var cross = 0.0'f64
        var decodedPower = 0.0'f64
        for frame in 3_072 until 10_240
        {
            let original = cast(f64, input[(frame - 1_024) * 2 + channel])
            let actual = cast(f64, decoded[frame * 2 + channel])
            error += (original - actual) * (original - actual)
            power += original * original
            decodedPower += actual * actual
            cross += original * actual
        }
        Swag.require(Math.sqrt(error / power) < 0.2)
        Swag.require(cross / Math.sqrt(power * decodedPower) > 0.9)
    }
}

// The full profile reconstructs system audio tones well above the speech band.
#test
{
    for frequency in [8_000.0'f64, 12_000.0, 16_000.0]
    {
        let path = Path.combine(Env.getSpecialDirectory(.Temp),
                                Format.toString("aac-software-high-%.aac", Guid128.random()))
        defer discard catch File.delete(path)
        var encoder = expect Aac.Encoder.create(48_000, 1)
        var source: [8 * 1_024] s16
        var file: Array'u8
        var packets: Array'SoundPacket
        for frame in source.count do
            source[frame] = cast(s16, Math.round(9_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                    frequency * frame / 48_000.0)))
        for block in 8
        {
            var packet: Array'u8
            expect encoder.encode(Swag.makeSlice(&source[block * 1_024], 1_024), &packet)
            packets.add({file.count, cast(u32, packet.count), 1_024})
            file.add(packet.toSlice())
        }
        discard expect File.writeAllBytes(path.toString(), file.toSlice())
        let sound = expect SoundFile.openPacketStream(path.toString(), .AacLc, 48_000, 1,
                                                      source.count, packets.toSlice(), encoder.decoderConfig())
        var decoded: Array's16
        expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
        {
            decoded.add(part)
            return true
        })
        var error = 0.0'f64
        var power = 0.0'f64
        var cross = 0.0'f64
        var decodedPower = 0.0'f64
        for frame in 3_072 until 7_168
        {
            let original = cast(f64, source[frame - 1_024])
            let actual = cast(f64, decoded[frame])
            error += (original - actual) * (original - actual)
            power += original * original
            decodedPower += actual * actual
            cross += original * actual
        }
        Swag.require(Math.sqrt(error / power) < 0.2)
        Swag.require(cross / Math.sqrt(power * decodedPower) > 0.9)
    }
}

// The bounded voice profile retains 3.5 kHz detail and rejects 6 kHz audio.
#test
{
    for frequency in [3_500.0'f64, 6_000.0]
    {
        let path = Path.combine(Env.getSpecialDirectory(.Temp),
                                Format.toString("aac-software-band-%.aac", Guid128.random()))
        defer discard catch File.delete(path)
        var encoder = expect Aac.Encoder.create(48_000, 1, .Voice)
        Swag.require(encoder.upperFrequencyHz() == 4_125)
        var source: [8 * 1_024] s16
        var file: Array'u8
        var packets: Array'SoundPacket
        for frame in source.count do
            source[frame] = cast(s16, Math.round(9_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                    frequency * frame / 48_000.0)))
        for block in 8
        {
            var packet: Array'u8
            expect encoder.encode(Swag.makeSlice(&source[block * 1_024], 1_024), &packet)
            packets.add({file.count, cast(u32, packet.count), 1_024})
            file.add(packet.toSlice())
        }
        discard expect File.writeAllBytes(path.toString(), file.toSlice())
        let sound = expect SoundFile.openPacketStream(path.toString(), .AacLc, 48_000, 1,
                                                      source.count, packets.toSlice(), encoder.decoderConfig())
        var decoded: Array's16
        expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
        {
            decoded.add(part)
            return true
        })
        var inputPower = 0.0'f64
        var outputPower = 0.0'f64
        for frame in 3_072 until 7_168
        {
            inputPower += cast(f64, source[frame - 1_024]) * source[frame - 1_024]
            outputPower += cast(f64, decoded[frame]) * decoded[frame]
        }
        let ratio = Math.sqrt(outputPower / inputPower)
        if frequency == 3_500.0 do
            Swag.require(ratio > 0.7 and ratio < 1.1)
        else do
            Swag.require(ratio < 0.1)
    }
}

// A harmonic mixture spread across the full spectrum retains its combined waveform.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("aac-software-music-%.aac", Guid128.random()))
    defer discard catch File.delete(path)
    var encoder = expect Aac.Encoder.create(48_000, 2)
    var source: [8 * 1_024 * 2] s16
    var file: Array'u8
    var packets: Array'SoundPacket
    for frame in 8 * 1_024
    {
        let time = frame / 48_000.0
        let value = 5_000.0 * Math.sin(Math.ConstF64.TwoPi * 200.0 * time) +
                    3_000.0 * Math.sin(Math.ConstF64.TwoPi * 600.0 * time) +
                    2_000.0 * Math.sin(Math.ConstF64.TwoPi * 1_400.0 * time) +
                    1_500.0 * Math.sin(Math.ConstF64.TwoPi * 2_800.0 * time) +
                    1_800.0 * Math.sin(Math.ConstF64.TwoPi * 7_000.0 * time) +
                    1_200.0 * Math.sin(Math.ConstF64.TwoPi * 12_000.0 * time) +
                    900.0 * Math.sin(Math.ConstF64.TwoPi * 16_000.0 * time)
        source[frame * 2] = cast(s16, Math.round(value))
        source[frame * 2 + 1] = cast(s16, Math.round(value * 0.6))
    }
    for block in 8
    {
        var packet: Array'u8
        expect encoder.encode(Swag.makeSlice(&source[block * 1_024 * 2], 1_024 * 2), &packet)
        Swag.require(packet.count < 8_191)
        packets.add({file.count, cast(u32, packet.count), 1_024})
        file.add(packet.toSlice())
    }
    discard expect File.writeAllBytes(path.toString(), file.toSlice())
    let sound = expect SoundFile.openPacketStream(path.toString(), .AacLc, 48_000, 2,
                                                  8 * 1_024, packets.toSlice(), encoder.decoderConfig())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == source.count)
    for channel in 2
    {
        var error = 0.0'f64
        var power = 0.0'f64
        var cross = 0.0'f64
        var decodedPower = 0.0'f64
        for frame in 3_072 until 7_168
        {
            let original = cast(f64, source[(frame - 1_024) * 2 + channel])
            let actual = cast(f64, decoded[frame * 2 + channel])
            error += (original - actual) * (original - actual)
            power += original * original
            decodedPower += actual * actual
            cross += original * actual
        }
        Swag.require(Math.sqrt(error / power) < 0.25)
        Swag.require(cross / Math.sqrt(power * decodedPower) > 0.9)
    }
}

// An impulse is represented as audio, then two zero packets drain the transform overlap.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("aac-software-impulse-%.aac", Guid128.random()))
    defer discard catch File.delete(path)
    var encoder = expect Aac.Encoder.create(48_000, 1)
    var file: Array'u8
    var packets: Array'SoundPacket
    var source: [6 * 1_024] s16
    source[2 * 1_024 + 512] = 15_000
    for block in 6
    {
        var packet: Array'u8
        expect encoder.encode(Swag.makeSlice(&source[block * 1_024], 1_024), &packet)
        packets.add({file.count, cast(u32, packet.count), 1_024})
        file.add(packet.toSlice())
    }
    discard expect File.writeAllBytes(path.toString(), file.toSlice())
    let sound = expect SoundFile.openPacketStream(path.toString(), .AacLc, 48_000, 1,
                                                  source.count, packets.toSlice(), encoder.decoderConfig())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    var peak = 0's32
    var peakAt = 0'u64
    for frame in decoded.count
    {
        let magnitude = Math.abs(cast(s32, decoded[frame]))
        if magnitude > peak
        {
            peak = magnitude
            peakAt = frame
        }
    }
    Swag.require(peak > 1_000 and peakAt >= 3 * 1_024 + 480 and peakAt < 3 * 1_024 + 544)
    for frame in 5 * 1_024 until decoded.count do
        Swag.require(decoded[frame] == 0)
}

// Dense stereo spectra exercise every scalefactor band, sign bit, and packet-size bound.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("aac-software-dense-%.aac", Guid128.random()))
    defer discard catch File.delete(path)
    var encoder = expect Aac.Encoder.create(48_000, 2)
    var source: [8 * 1_024 * 2] s16
    var state = 0x12345678'u32
    for index in source.count
    {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        source[index] = cast(s16, cast(s32, state % 24_001) - 12_000)
    }
    var file: Array'u8
    var packets: Array'SoundPacket
    for block in 8
    {
        var packet: Array'u8
        expect encoder.encode(Swag.makeSlice(&source[block * 1_024 * 2], 1_024 * 2), &packet)
        Swag.require(packet.count > 100 and packet.count < 8_191)
        packets.add({file.count, cast(u32, packet.count), 1_024})
        file.add(packet.toSlice())
    }
    discard expect File.writeAllBytes(path.toString(), file.toSlice())
    let sound = expect SoundFile.openPacketStream(path.toString(), .AacLc, 48_000, 2,
                                                  8 * 1_024, packets.toSlice(), encoder.decoderConfig())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == source.count)
    var error = 0.0'f64
    var power = 0.0'f64
    var cross = 0.0'f64
    var decodedPower = 0.0'f64
    for frame in 3_072 until 7_168
    {
        let original = cast(f64, source[(frame - 1_024) * 2])
        let actual = cast(f64, decoded[frame * 2])
        error += (original - actual) * (original - actual)
        power += original * original
        decodedPower += actual * actual
        cross += original * actual
    }
    Swag.require(Math.sqrt(error / power) < 0.15)
    Swag.require(cross / Math.sqrt(power * decodedPower) > 0.95)
    Swag.require(file.count < 8 * 2_048)
}

// Invalid sample counts and configurations are rejected without consuming a pending block.
#test
{
    var rejected: Swag.Error
    discard catch Aac.Encoder.create(48_000, 3) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch Aac.Encoder.create(32_000, 1) as rejected
    Swag.require(rejected.value() is BadParameterError)

    var encoder = expect Aac.Encoder.create(48_000, 1)
    var short: [1_023] s16
    var packet: Array'u8
    discard catch encoder.encode(Swag.makeSlice(&short[0], short.count), &packet) as rejected
    Swag.require(rejected.value() is BadParameterError and packet.isEmpty())
    var complete: [1_024] s16
    expect encoder.encode(Swag.makeSlice(&complete[0], complete.count), &packet)
    Swag.require(not packet.isEmpty())
}

// Silence uses the minimal AAC packet after one overlap tail, across both profiles.
#test
{
    for bandwidth in [Aac.Bandwidth.Full, .Voice]
    {
        for channels in [1'u16, 2]
        {
            var encoder = expect Aac.Encoder.create(48_000, channels, bandwidth)
            let silent = expect Aac.SilenceEncoder.create(48_000, channels)
            var input: [2 * 1_024] s16
            var packet: Array'u8
            expect encoder.encode(Swag.makeSlice(&input[0], 1_024 * channels), &packet)
            Swag.require(packet.count == silent.packet().count)
            Swag.require(Memory.compare(packet.toSlice().buffer, silent.packet().buffer, packet.count) == 0)

            input[512 * channels] = 10_000
            expect encoder.encode(Swag.makeSlice(&input[0], 1_024 * channels), &packet)
            Swag.require(packet.count > silent.packet().count)
            input[512 * channels] = 0
            expect encoder.encode(Swag.makeSlice(&input[0], 1_024 * channels), &packet)
            Swag.require(packet.count > silent.packet().count)
            expect encoder.encode(Swag.makeSlice(&input[0], 1_024 * channels), &packet)
            Swag.require(packet.count == silent.packet().count)
            Swag.require(Memory.compare(packet.toSlice().buffer, silent.packet().buffer, packet.count) == 0)
        }
    }
}
