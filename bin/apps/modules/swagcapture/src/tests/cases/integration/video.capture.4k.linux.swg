#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core, Pixel, Video

// Measures one second of real 4K X11 acquisition, conversion, H.264 and fragmented MP4.
// Run this opt-in test on an X11 server with a 3840x2160 root, such as DISPLAY=:92.
#[Swag.TestTag("stress.capture.x11.4k")]
#test
{
    const Width = 3840
    const Height = 2160
    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("swag-capture-4k60-%.mp4", Guid64.random()).toString())
    defer discard catch File.delete(path)
    var session = expect VideoCaptureSession.create(
        path, {0, 0, Width, Height}, expect FrameRate.create(60, 1), false)
    var watch: Time.Stopwatch
    watch.start()
    for frame in 60'u64 do
        Swag.require(expect session.captureAt(frame * 16_667))
    expect session.end()
    watch.stop()
    Console.printf("Real X11 software MP4 4K60: % us for 60 frames, % bytes\n",
                   watch.elapsedMicroseconds(), (expect File.info(path)).size)
    let encodedAt = Time.monotonicMicroseconds()
    Swag.require(session.frameCount() == 60 and session.repeatedFrameCount() == 0)
    var reader = expect Reader.open(path)
    let openedAt = Time.monotonicMicroseconds()
    Swag.require(reader.frameCount() == 60 and reader.audioTrackCount() == 0)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 59)
    let decodedAt = Time.monotonicMicroseconds()
    var expected: Nv12Frame
    expect expected.convertFrom(&session.picture)
    Swag.require(Slice.equals(decoded.luma.toSlice(), expected.luma()))
    Console.printf("Real X11 4K60 validation: open % us, last-frame decode % us, compare % us\n",
                   openedAt - encodedAt, decodedAt - openedAt,
                   Time.monotonicMicroseconds() - decodedAt)
}

// Measures the same 4K screen acquisition while encoding a live stereo AAC track.
#[Swag.TestTag("stress.capture.x11.4k.av")]
#test
{
    const Width = 3840
    const Height = 2160
    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("swag-capture-4k60-av-%.mp4", Guid64.random()).toString())
    defer discard catch File.delete(path)
    let configs: [1] Mp4.SoftwareAudioConfig = [{48_000, 2, .Full}]
    var session = expect VideoCaptureSession.create(
        path, {0, 0, Width, Height}, expect FrameRate.create(60, 1), false,
        Swag.makeSlice(&configs[0], configs.count))
    var samples: [2 * 1_024] s16
    for frame in 1_024'u64
    {
        samples[frame * 2] = cast(s16, Math.round(8_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                      1_000.0 * frame / 48_000.0)))
        samples[frame * 2 + 1] = cast(s16, Math.round(6_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                          1_500.0 * frame / 48_000.0)))
    }
    var watch: Time.Stopwatch
    watch.start()
    var audioBlocks = 0'u64
    for frame in 60'u64
    {
        Swag.require(expect session.captureAt(frame * 16_667))
        while audioBlocks < 47 and audioBlocks * 1_024 < (frame + 1) * 800
        {
            expect session.addAudioFrames(Swag.makeSlice(&samples[0], samples.count))
            audioBlocks += 1
        }
    }
    expect session.end()
    watch.stop()
    Console.printf("Real X11 software MP4 4K60 with AAC: % us for 60 frames and 48 sound packets\n",
                   watch.elapsedMicroseconds())
    let summary = expect Mp4.summarizeFragmentedRecording(path)
    Swag.require(summary.video.packetCount == 60 and summary.audioTracks.count == 1)
    Swag.require(summary.audioTracks[0].packetCount == 48 and not summary.hasIncompleteTail)
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 60 and reader.audioTrackCount() == 1)
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleFrameCount() == 47 * 1_024)
    var pcm: Array's16
    expect sound.decodePcm16(func|pcm = &pcm|(part: const [..] s16)->bool
    {
        pcm.add(part)
        return true
    })
    Swag.require(pcm.count == 47 * 1_024 * 2)
    var power = 0.0'f64
    for sample in pcm do
        power += cast(f64, sample) * sample
    Swag.require(Math.sqrt(power / pcm.count) > 2_000)
}
