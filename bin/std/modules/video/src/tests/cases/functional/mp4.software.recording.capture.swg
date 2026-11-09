#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Audio, Pixel

// A lost microphone block becomes silence on the synchronized MP4 audio track.
#test
{
    let path = videoTempPath("mp4-software-capture-gap", "mp4")
    defer discard catch File.delete(path)
    let image = Image.create(32, 16, .BGRA8)
    Memory.set(image.pixels.storage(), 90, image.pixels.count)
    var queue = expect CaptureQueue.create(48_000, 1, 0, 48_000,
                                           blockFrames: 1_024, tolerance: 0)
    var signal: [1_024] s16
    for sample in signal.count do
        signal[sample] = cast(s16, Math.round(10_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                   1_000.0 * sample / 48_000.0)))
    discard expect queue.push(Swag.makeSlice(&signal[0], signal.count), 0)
    expect queue.markLost(1_024)
    expect queue.markRestored(2_048)
    discard expect queue.push(Swag.makeSlice(&signal[0], signal.count), 2_048)

    var recorder = expect Mp4.SoftwareRecording.create(path, 32, 16, 90_000, 48_000, 1)
    let pacer = expect FramePacer.create(expect FrameRate.create(60, 1), 48_000, 90_000)
    for frame in 5'u64 do
        expect recorder.addFrame(&image, expect pacer.slotAt(frame))
    var captured: Array's16
    var info: CaptureBlock
    var sawGap = false
    var sawInterruption = false
    var silence: [1_024] s16
    while queue.pop(&captured, &info)
    {
        if info.gapFrames
        {
            Swag.require(info.gapFrames == 1_024)
            expect recorder.addAudioFrames(Swag.makeSlice(&silence[0], silence.count))
            sawGap = true
        }
        if info.sourceInterrupted do
            sawInterruption = true
        expect recorder.addAudioFrames(captured.toSlice())
    }
    Swag.require(sawGap and sawInterruption)
    expect recorder.end()
    Swag.require(recorder.videoFrameCount() == 5 and recorder.audioInputFrameCount() == 3 * 1_024)
    Swag.require(recorder.audioPacketCount() == 4)

    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 5 and reader.audioTrackCount() == 1)
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleFrameCount() == 3 * 1_024)
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == 3 * 1_024)
    var before = 0.0'f64
    var gap = 0.0'f64
    var after = 0.0'f64
    for sample in 1_024'u64
    {
        before += cast(f64, decoded[sample]) * decoded[sample]
        gap += cast(f64, decoded[1_024 + sample]) * decoded[1_024 + sample]
        after += cast(f64, decoded[2_048 + sample]) * decoded[2_048 + sample]
    }
    Swag.require(Math.sqrt(before / 1_024) > 4_000)
    Swag.require(Math.sqrt(gap / 1_024) < 500)
    Swag.require(Math.sqrt(after / 1_024) > 4_000)
}
