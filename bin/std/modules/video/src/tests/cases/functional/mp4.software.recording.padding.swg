#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Audio, Pixel

func checkSoftwareAacTail(rate: u32, channels: u16) fail
{
    const Frames = 2_501'u64
    let path = videoTempPath("mp4-software-aac-tail", "mp4")
    defer discard catch File.delete(path)
    let image = videoGrayImage(16, 16, 100)
    var recorder = try Mp4.SoftwareRecording.create(path, 16, 16, 90_000,
                                                    rate, channels)
    let pacer = try FramePacer.create(try FrameRate.create(30, 1), rate, 90_000)
    for frame in 4'u64 do
        try recorder.addFrame(&image, try pacer.slotAt(frame))

    var source: Array's16
    source.resize(Frames * channels)
    for frame in Frames
    {
        let value = cast(s16, Math.round(8_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                              500.0 * frame / rate)))
        for channel in channels do
            source[frame * channels + channel] = value
    }
    try recorder.addAudioFrames(source.toSlice())
    try recorder.flush()

    // The incomplete recording remains readable. Its partial AAC packet has not been drained.
    var prefix = try Reader.open(path)
    Swag.require(prefix.audioTrackCount() == 1)
    Swag.require((unwrap prefix.audioTrack(0)).sampleFrameCount() == 1_024)

    try recorder.end()
    Swag.require(recorder.audioInputFrameCount() == Frames)
    Swag.require(recorder.audioPacketCount() == 4)
    var reader = try Reader.open(path)
    Swag.require(reader.frameCount() == 4 and reader.audioTrackCount() == 1)
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleFrameCount() == Frames)
    Swag.require(Math.abs(sound.timelineStartSeconds()) < 0.000001)
    var decoded: Array's16
    try sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == Frames * channels)

    // Inspect the exact final edit: the media starts after one AAC priming packet.
    var editCount = 0'u32
    let raw = try File.readAllBytes(path)
    for offset in raw.count - 3
    {
        if raw[offset] == 'e' and raw[offset + 1] == 'd' and
           raw[offset + 2] == 't' and raw[offset + 3] == 's' do
            editCount += 1
    }
    Swag.require(editCount == 2)
}

// Final AAC padding is omitted at 48 kHz and at the non-integral 44.1 kHz movie ratio.
#test
{
    expect checkSoftwareAacTail(48_000, 1)
    expect checkSoftwareAacTail(44_100, 2)
}

// Independently drained microphone and system tracks keep their own final lengths.
#test
{
    let path = videoTempPath("mp4-software-two-aac-tails", "mp4")
    defer discard catch File.delete(path)
    let configs: [2] Mp4.SoftwareAudioConfig = [{48_000, 1}, {48_000, 2}]
    var recorder = expect Mp4.SoftwareRecording.createWithAudioTracks(
        path, 16, 16, 90_000, Swag.makeSlice(&configs[0], configs.count))
    let image = videoGrayImage(16, 16, 96)
    let pacer = expect FramePacer.create(expect FrameRate.create(30, 1), 48_000, 90_000)
    for frame in 3'u64 do
        expect recorder.addFrame(&image, expect pacer.slotAt(frame))
    var mic: [2_501] s16
    var system: [1_297 * 2] s16
    for frame in mic.count do
        mic[frame] = cast(s16, frame % 101)
    for frame in 1_297'u64
    {
        system[frame * 2] = cast(s16, frame % 71)
        system[frame * 2 + 1] = cast(s16, frame % 53)
    }
    expect recorder.addAudioFrames(Swag.makeSlice(&mic[0], mic.count), 0)
    expect recorder.addAudioFrames(Swag.makeSlice(&system[0], system.count), 1)
    expect recorder.end()
    var reader = expect Reader.open(path)
    Swag.require(reader.audioTrackCount() == 2)
    const Expected: [2] u64 = [2_501, 1_297]
    const Channels: [2] u64 = [1, 2]
    for index in 2'u64
    {
        let sound = unwrap reader.audioTrack(cast(u32, index))
        Swag.require(sound.sampleFrameCount() == Expected[index])
        var decoded: Array's16
        expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
        {
            decoded.add(part)
            return true
        })
        Swag.require(decoded.count == Expected[index] * Channels[index])
    }
}
