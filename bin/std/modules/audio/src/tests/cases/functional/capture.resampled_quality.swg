#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Realistic 10 ms 96/44.1 kHz stereo packets retain music bands and impulse timing at 48 kHz.
#test
{
    for sourceRate in [96_000'u32, 44_100]
    {
        var queue = expect CaptureQueue.create(48_000, 2, 0, 10_000_000,
                                               blockFrames: 1_024, slots: 64, tolerance: 0)
        var feeder = expect CaptureResampledFeeder.create(&queue, sourceRate)
        let packetFrames = sourceRate / 100
        var packet: [960 * 2] f32
        const LeftImpulseTime = 0.18'f64
        const RightImpulseTime = 0.21'f64
        let leftImpulse = cast(u64, Math.round(LeftImpulseTime * sourceRate))
        let rightImpulse = cast(u64, Math.round(RightImpulseTime * sourceRate))
        for packetIndex in 25
        {
            for frame in packetFrames
            {
                let sourceFrame = packetIndex * packetFrames + frame
                let time = cast(f64, sourceFrame) / sourceRate
                var left = 0.0'f64
                var right = 0.0'f64
                if time < 0.15
                {
                    left = 0.20 * Math.sin(Math.ConstF64.TwoPi * 1_000.0 * time) +
                           0.10 * Math.sin(Math.ConstF64.TwoPi * 8_000.0 * time) +
                           0.08 * Math.sin(Math.ConstF64.TwoPi * 14_000.0 * time)
                    right = 0.18 * Math.sin(Math.ConstF64.TwoPi * 2_000.0 * time) +
                            0.09 * Math.sin(Math.ConstF64.TwoPi * 10_000.0 * time) +
                            0.07 * Math.sin(Math.ConstF64.TwoPi * 16_000.0 * time)
                }
                if sourceFrame == leftImpulse do
                    left = 0.7
                if sourceFrame == rightImpulse do
                    right = -0.65
                packet[frame * 2] = cast(f32, left)
                packet[frame * 2 + 1] = cast(f32, right)
            }
            expect feeder.pushFloat32(Swag.makeSlice(&packet[0], packetFrames * 2),
                                      packetIndex * 100_000, packetIndex * packetFrames)
        }
        expect feeder.finish()
        var pcm: Array's16
        var block: Array's16
        var info: CaptureBlock
        var nextSample = 0'u64
        while queue.pop(&block, &info)
        {
            Swag.require(info.startSample == nextSample and info.gapFrames == 0)
            nextSample += info.frameCount
            pcm.add(block.toSlice())
        }
        Swag.require(nextSample >= 12_000 and nextSample <= 12_001 and pcm.count == nextSample * 2)
        for channel in 2
        {
            var sourcePower = 0.0'f64
            var outputPower = 0.0'f64
            var cross = 0.0'f64
            var error = 0.0'f64
            for frame in 1_000 until 5_000
            {
                let time = frame / 48_000.0
                let expected = channel == 0 ?
                               0.20 * Math.sin(Math.ConstF64.TwoPi * 1_000.0 * time) +
                               0.10 * Math.sin(Math.ConstF64.TwoPi * 8_000.0 * time) +
                               0.08 * Math.sin(Math.ConstF64.TwoPi * 14_000.0 * time) :
                               0.18 * Math.sin(Math.ConstF64.TwoPi * 2_000.0 * time) +
                               0.09 * Math.sin(Math.ConstF64.TwoPi * 10_000.0 * time) +
                               0.07 * Math.sin(Math.ConstF64.TwoPi * 16_000.0 * time)
                let original = expected * 32_768.0
                let actual = cast(f64, pcm[frame * 2 + channel])
                sourcePower += original * original
                outputPower += actual * actual
                cross += original * actual
                error += (original - actual) * (original - actual)
            }
            Swag.require(cross / Math.sqrt(sourcePower * outputPower) > 0.98)
            Swag.require(Math.sqrt(error / sourcePower) < 0.15)
        }
        for channel in 2
        {
            let expected = channel == 0 ? 8_640 : 10_080
            var peak = 0's32
            var peakAt = 0'u64
            for frame in expected - 128 until expected + 128
            {
                let magnitude = Math.abs(cast(s32, pcm[frame * 2 + channel]))
                if magnitude > peak
                {
                    peak = magnitude
                    peakAt = frame
                }
            }
            Swag.require(peak > 10_000 and Math.abs(cast(s64, peakAt) - expected) <= 2)
        }
    }
}

// A replaced 96 kHz device can resume at 44.1 kHz without smearing the old filter state.
#test
{
    var queue = expect CaptureQueue.create(48_000, 2, 0, 10_000_000,
                                           blockFrames: 1_024, slots: 64, tolerance: 0)
    var first = expect CaptureResampledFeeder.create(&queue, 96_000)
    var firstPacket: [960 * 2] f32
    for sample in firstPacket.count do
        firstPacket[sample] = 0.25
    for packet in 10 do
        expect first.pushFloat32(Swag.makeSlice(&firstPacket[0], firstPacket.count),
                                 packet * 100_000, packet * 960)
    expect first.finish()
    var samples: Array's16
    var info: CaptureBlock
    var end = 0'u64
    while queue.pop(&samples, &info)
    {
        Swag.require(info.startSample == end and info.gapFrames == 0)
        end += info.frameCount
    }
    Swag.require(end == 4_800)

    expect queue.markLost(1_000_000)
    expect queue.markRestored(1_500_000)
    var second = expect CaptureResampledFeeder.create(&queue, 44_100)
    var secondPacket: [441 * 2] f32
    for sample in secondPacket.count do
        secondPacket[sample] = -0.25
    for packet in 10 do
        expect second.pushFloat32(Swag.makeSlice(&secondPacket[0], secondPacket.count),
                                  1_500_000 + packet * 100_000, packet * 441)
    expect second.finish()
    var restored = false
    var resumeSamples = 0'u64
    while queue.pop(&samples, &info)
    {
        if not restored
        {
            Swag.require(info.sourceInterrupted and info.startSample == 7_200 and
                         info.gapFrames == 2_400)
            restored = true
        }
        else do
            Swag.require(not info.sourceInterrupted and info.gapFrames == 0)
        for frame in info.frameCount
        {
            if resumeSamples > 128 and resumeSamples < 4_700
            {
                Swag.require(Math.abs(cast(s32, samples[frame * 2]) + 8_192) <= 250)
                Swag.require(Math.abs(cast(s32, samples[frame * 2 + 1]) + 8_192) <= 250)
            }
            resumeSamples += 1
        }
        end = info.startSample + info.frameCount
    }
    Swag.require(restored and resumeSamples >= 4_800 and resumeSamples <= 4_801 and
                 end == queue.sampleEnd())
}
