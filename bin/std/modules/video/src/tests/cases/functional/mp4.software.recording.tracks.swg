#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors, Audio, Pixel

// Microphone and system sound remain separate AAC tracks with aligned audible time zero.
#test
{
    let path = videoTempPath("mp4-software-two-audio-tracks", "mp4")
    defer discard catch File.delete(path)
    let image = Image.create(32, 16, .BGRA8)
    Memory.set(image.pixels.storage(), 110, image.pixels.count)
    let configs: [2] Mp4.SoftwareAudioConfig = [{48_000, 1, .Voice},
                                                {48_000, 2, .Full}]
    var recorder = expect Mp4.SoftwareRecording.createWithAudioTracks(
        path, 32, 16, 90_000, Swag.makeSlice(&configs[0], configs.count))
    Swag.require(recorder.audioTrackCount() == 2 and recorder.videoPrerollTicks() == 1_920)
    let pacer = expect FramePacer.create(expect FrameRate.create(60, 1), 48_000, 90_000)
    for frame in 13'u64 do
        expect recorder.addFrame(&image, expect pacer.slotAt(frame))

    var microphone: [10 * 1_024] s16
    var system: [10 * 1_024 * 2] s16
    for frame in 10 * 1_024
    {
        microphone[frame] = cast(s16, Math.round(9_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                      1_000.0 * frame / 48_000.0)))
        system[frame * 2] = cast(s16, Math.round(7_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                     2_000.0 * frame / 48_000.0)))
        system[frame * 2 + 1] = cast(s16, Math.round(6_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                         3_000.0 * frame / 48_000.0)))
    }
    for block in 10'u64
    {
        expect recorder.addAudioFrames(Swag.makeSlice(&microphone[block * 1_024], 1_024), 0)
        expect recorder.addAudioFrames(Swag.makeSlice(&system[block * 2 * 1_024], 2 * 1_024), 1)
    }
    Swag.require(expect recorder.audioInputFrameCountOf(0) == 10 * 1_024)
    Swag.require(expect recorder.audioInputFrameCountOf(1) == 10 * 1_024)
    Swag.require(expect recorder.audioPacketCountOf(0) == 10)
    Swag.require(expect recorder.audioPacketCountOf(1) == 10)
    expect recorder.end()
    Swag.require(expect recorder.audioPacketCountOf(0) == 11)
    Swag.require(expect recorder.audioPacketCountOf(1) == 11)

    let summary = expect Mp4.summarizeFragmentedRecording(path)
    Swag.require(summary.video.packetCount == 13 and summary.audioTracks.count == 2)
    Swag.require(summary.audioTracks[0].packetCount == 11 and summary.audioTracks[1].packetCount == 11)
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 13 and reader.audioTrackCount() == 2)
    for trackIndex in 2'u64
    {
        let sound = unwrap reader.audioTrack(cast(u32, trackIndex))
        Swag.require(sound.sampleFrameCount() == 10 * 1_024)
        Swag.require(Math.abs(sound.timelineStartSeconds()) < 0.000001)
        var pcm: Array's16
        expect sound.decodePcm16(func|pcm = &pcm|(part: const [..] s16)->bool
        {
            pcm.add(part)
            return true
        })
        let channels = trackIndex == 0 ? 1'u64 : 2'u64
        Swag.require(pcm.count == 10 * 1_024 * channels)
        for channel in channels
        {
            var error = 0.0'f64
            var power = 0.0'f64
            var cross = 0.0'f64
            var decodedPower = 0.0'f64
            for frame in 2_048 until 8_192
            {
                let expected = trackIndex == 0 ? cast(f64, microphone[frame]) :
                               cast(f64, system[frame * 2 + channel])
                let actual = cast(f64, pcm[frame * channels + channel])
                error += (expected - actual) * (expected - actual)
                power += expected * expected
                decodedPower += actual * actual
                cross += expected * actual
            }
            Swag.require(Math.sqrt(error / power) < 0.2)
            Swag.require(cross / Math.sqrt(power * decodedPower) > 0.9)
        }
    }
}

// Different audio sample clocks and unknown tracks fail without accepting packets.
#test
{
    let path = videoTempPath("mp4-software-track-errors", "mp4")
    defer discard catch File.delete(path)
    const MixedRates: [2] Mp4.SoftwareAudioConfig = [{48_000, 1}, {44_100, 2}]
    var rejected: Swag.Error
    discard catch Mp4.SoftwareRecording.createWithAudioTracks(
        path, 16, 16, 90_000, Swag.makeSlice(&MixedRates[0], MixedRates.count)) as rejected
    Swag.require(rejected.value() is BadParameterError)
    let configs: [2] Mp4.SoftwareAudioConfig = [{48_000, 1}, {48_000, 2}]
    var recorder = expect Mp4.SoftwareRecording.createWithAudioTracks(
        path, 16, 16, 90_000, Swag.makeSlice(&configs[0], configs.count))
    const Pair: [2] s16 = [10, 20]
    discard catch recorder.addAudioFrames(Swag.makeSlice(&Pair[0], Pair.count), 2) as rejected
    Swag.require(rejected.value() is BadParameterError)
    Swag.require(expect recorder.audioInputFrameCountOf(0) == 0)
    Swag.require(expect recorder.audioInputFrameCountOf(1) == 0)
    let image = Image.create(16, 16, .BGRA8)
    let pacer = expect FramePacer.create(expect FrameRate.create(60, 1), 48_000, 90_000)
    expect recorder.addFrame(&image, expect pacer.slotAt(0))
    expect recorder.end()
}

// The recorder bounds its independently encoded sound-track count at four.
#test
{
    let path = videoTempPath("mp4-software-track-limits", "mp4")
    defer discard catch File.delete(path)
    var rejected: Swag.Error
    const TooMany: [5] Mp4.SoftwareAudioConfig = [{48_000, 1}, {48_000, 1},
                                                  {48_000, 1}, {48_000, 1},
                                                  {48_000, 1}]
    discard catch Mp4.SoftwareRecording.createWithAudioTracks(
        path, 16, 16, 90_000, Swag.makeSlice(&TooMany[0], TooMany.count)) as rejected
    Swag.require(rejected.value() is BadParameterError)
}

// A video-only recording has no AAC track, no preroll and no sound-device requirement.
#test
{
    let path = videoTempPath("mp4-software-video-only", "mp4")
    defer discard catch File.delete(path)
    var recorder = expect Mp4.SoftwareRecording.createVideoOnly(path, 32, 16, 90_000)
    Swag.require(recorder.videoPrerollTicks() == 0 and recorder.audioTrackCount() == 0)
    Swag.require(recorder.audioInputFrameCount() == 0 and recorder.audioPacketCount() == 0)
    let image = Image.create(32, 16, .BGRA8)
    Memory.set(image.pixels.storage(), 81, image.pixels.count)
    let pacer = expect FramePacer.create(expect FrameRate.create(60, 1), 1_000_000, 90_000)
    for frame in 4'u64 do
        expect recorder.addFrame(&image, expect pacer.slotAt(frame))
    var rejected: Swag.Error
    discard catch recorder.addAudioFrames([]) as rejected
    Swag.require(rejected.value() is BadParameterError)
    expect recorder.end()
    Swag.require(recorder.videoFrameCount() == 4)
    let summary = expect Mp4.summarizeFragmentedRecording(path)
    Swag.require(summary.video.packetCount == 4 and summary.audioTracks.count == 0)
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 4 and reader.audioTrackCount() == 0)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 3)
    var expected: Nv12Frame
    expect expected.convertFrom(&image)
    Swag.require(Slice.equals(decoded.luma.toSlice(), expected.luma()))
}

// The 44.1 kHz priming boundary is rounded down on a 90 kHz video clock, preserving 1024 samples.
#test
{
    let path = videoTempPath("mp4-software-44100-preroll", "mp4")
    defer discard catch File.delete(path)
    var recorder = expect Mp4.SoftwareRecording.create(path, 16, 16, 90_000, 44_100, 1)
    Swag.require(recorder.videoPrerollTicks() == 2_089)
    let image = Image.create(16, 16, .BGRA8)
    let pacer = expect FramePacer.create(expect FrameRate.create(60, 1), 44_100, 90_000)
    for frame in 14'u64 do
        expect recorder.addFrame(&image, expect pacer.slotAt(frame))
    var signal: [10 * 1_024] s16
    for frame in signal.count do
        signal[frame] = cast(s16, Math.round(9_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                 1_000.0 * frame / 44_100.0)))
    expect recorder.addAudioFrames(Swag.makeSlice(&signal[0], signal.count))
    expect recorder.end()
    var reader = expect Reader.open(path)
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleFrameCount() == signal.count)
    Swag.require(Math.abs(sound.timelineStartSeconds()) < 0.000012)
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == signal.count)
    var cross = 0.0'f64
    var sourcePower = 0.0'f64
    var decodedPower = 0.0'f64
    for frame in 2_048 until 8_192
    {
        let source = cast(f64, signal[frame])
        let actual = cast(f64, decoded[frame])
        cross += source * actual
        sourcePower += source * source
        decodedPower += actual * actual
    }
    Swag.require(cross / Math.sqrt(sourcePower * decodedPower) > 0.9)
}

// A clock too coarse to identify a single AAC sample cannot promise synchronized playback.
#test
{
    let path = videoTempPath("mp4-software-coarse-clock", "mp4")
    defer discard catch File.delete(path)
    var rejected: Swag.Error
    discard catch Mp4.SoftwareRecording.create(path, 16, 16, 1, 44_100, 1) as rejected
    Swag.require(rejected.value() is BadParameterError)
}
