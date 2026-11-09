#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A 96 kHz native float source survives resampling, an outage, AAC, and Swag decoding.
#test
{
    const SourceRate = 96_000'u32
    const OutputRate = 48_000'u32
    const ClockRate = 10_000_000'u64
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("audio-capture-resampled-aac-%.aac", Guid128.random()))
    defer discard catch File.delete(path)

    var queue = expect CaptureQueue.create(OutputRate, 2, 0, ClockRate,
                                           blockFrames: 1_024, slots: 8, tolerance: 0)
    var feeder = expect CaptureResampledFeeder.create(&queue, SourceRate)
    var track = expect CaptureAacTrack.create(&queue)
    var source: [960 * 2] f32
    var encoded: Array'u8
    var file: Array'u8
    var packets: Array'SoundPacket
    var info: CaptureAacPacket
    var synthetic = 0'u64
    var resumed = false
    for packet in 40
    {
        if packet == 20
        {
            expect feeder.suspendForIdle()
            expect queue.markLost(2_000_000)
            expect queue.markRestored(2_500_000)
        }
        let localPacket = packet < 20 ? packet : packet - 20
        let firstTick = (packet < 20 ? 0'u64 : 2_500_000) + localPacket * 100_000
        let firstFrame = localPacket * 960
        for frame in 960
        {
            let time = cast(f64, firstTick) / ClockRate + cast(f64, frame) / SourceRate
            source[frame * 2] = cast(f32,
                0.25 * Math.sin(Math.ConstF64.TwoPi * 1_000.0 * time) +
                0.08 * Math.sin(Math.ConstF64.TwoPi * 8_000.0 * time))
            source[frame * 2 + 1] = cast(f32,
                0.22 * Math.sin(Math.ConstF64.TwoPi * 2_000.0 * time) +
                0.07 * Math.sin(Math.ConstF64.TwoPi * 12_000.0 * time))
        }
        expect feeder.pushFloat32(Swag.makeSlice(&source[0], source.count), firstTick, firstFrame)
        while expect track.nextPacket(&encoded, &info)
        {
            Swag.require(info.startSample == packets.count * 1_024)
            synthetic += info.syntheticFrames
            resumed = resumed or info.sourceInterrupted
            packets.add({file.count, cast(u32, encoded.count), 1_024})
            file.add(encoded.toSlice())
        }
    }
    expect feeder.finish()
    while expect track.finish(&encoded, &info)
    {
        Swag.require(info.startSample == packets.count * 1_024)
        synthetic += info.syntheticFrames
        resumed = resumed or info.sourceInterrupted
        packets.add({file.count, cast(u32, encoded.count), 1_024})
        file.add(encoded.toSlice())
    }
    Swag.require(queue.sampleEnd() == 21_600 and track.inputFrameCount() == 21_600 and
                 synthetic == 2_400 and resumed and queue.droppedBlockCount() == 0)

    discard expect File.writeAllBytes(path.toString(), file.toSlice())
    let sound = expect SoundFile.openPacketStream(path.toString(), .AacLc, OutputRate, 2,
                                                  packets.count * 1_024, packets.toSlice(),
                                                  track.decoderConfig())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == packets.count * 1_024 * 2)
    for channel in 2
    {
        for start in [2_400'u64, 14_400]
        {
            var sourcePower = 0.0'f64
            var decodedPower = 0.0'f64
            var cross = 0.0'f64
            var error = 0.0'f64
            for frame in start until start + 4_800
            {
                let time = frame / 48_000.0
                let original = (channel == 0 ?
                                0.25 * Math.sin(Math.ConstF64.TwoPi * 1_000.0 * time) +
                                0.08 * Math.sin(Math.ConstF64.TwoPi * 8_000.0 * time) :
                                0.22 * Math.sin(Math.ConstF64.TwoPi * 2_000.0 * time) +
                                0.07 * Math.sin(Math.ConstF64.TwoPi * 12_000.0 * time)) * 32_768.0
                let actual = cast(f64, decoded[(frame + 1_024) * 2 + channel])
                sourcePower += original * original
                decodedPower += actual * actual
                cross += original * actual
                error += (original - actual) * (original - actual)
            }
            Swag.require(cross / Math.sqrt(sourcePower * decodedPower) > 0.96 and
                         Math.sqrt(error / sourcePower) < 0.28)
        }
        var gapPower = 0.0'f64
        for frame in 10_400 until 11_200
        {
            let sample = cast(f64, decoded[(frame + 1_024) * 2 + channel])
            gapPower += sample * sample
        }
        Swag.require(Math.sqrt(gapPower / 800) < 500)
    }
}
