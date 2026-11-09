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
