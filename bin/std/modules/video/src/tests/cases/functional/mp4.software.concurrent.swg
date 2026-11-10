#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Audio, Pixel

func concurrentAudioBlock(track, block: u64)->Array's16
{
    var result: #returntype
    result.resize(2 * 1_024)
    for frame in 1_024'u64
    {
        let time = cast(f64, block * 1_024 + frame) / 48_000
        result[frame * 2]     = cast(s16, Math.round(7_000 * Math.sin(Math.ConstF64.TwoPi * (440 + track * 220) * time)))
        result[frame * 2 + 1] = cast(s16, Math.round(5_000 * Math.sin(Math.ConstF64.TwoPi * (660 + track * 330) * time)))
    }

    return result
}

// Two AAC producers may encode and mux while the independent video producer writes pictures.
// Compare every compressed audio packet against sequential encoding, not only track lengths.
#test
{
    let path = videoTempPath("software-concurrent", "mp4")
    defer discard catch File.delete(path)
    const Configs: [2] Mp4.SoftwareAudioConfig = [{48_000, 2}, {48_000, 2}]
    var recording = expect Mp4.SoftwareRecording.createWithAudioTracks(path, 64, 48, 90_000, Configs)
    var start: Sync.Event
    start.init(true)
    var errors:  [2] Swag.Error
    var threads: [2] Threading.Thread
    for index in 2'u64
    {
        expect threads[index].init(func|recording = &recording, start = &start,
                                   error = &errors[index], index|(_)
        {
            start.wait()
            catch
            {
                for block in 32'u64
                {
                    let samples = concurrentAudioBlock(index, block)
                    try recording.addAudioFrames(samples.toSlice(), cast(u32, index))
                    Threading.Thread.yield()
                }
            }
            {
                error.capture(Swag.err)
            }
        })
        expect threads[index].start()
    }

    start.signal()
    let picture = videoGrayImage(64, 48, 96)
    for frame in 35'u64
    {
        expect recording.addFrame(&picture, FrameSlot{frame, frame * 3_000, 3_000, 0})
        if frame % 5 == 0 do
            expect recording.flush()
        Threading.Thread.yield()
    }

    for &thread in threads do
        thread.wait()
    for &error in errors do
        expect error.raise()
    expect recording.end()
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 35 and reader.audioTrackCount() == 2)
    discard expect reader.decodeFrame(34)
    var packets = expect Mp4.FragmentedPacketReader.open(path)
    for track in 2'u64
    {
        Swag.require(reader.audioTrack(cast(u32, track))!.sampleFrameCount() == 32 * 1_024)
        var encoder = expect Aac.StreamEncoder.create(48_000, 2)
        var expected, actual: Array'u8
        for block in 32'u64
        {
            let samples = concurrentAudioBlock(track, block)
            Swag.require(expect encoder.push(samples.toSlice(), &expected) == 1_024)
            let packet = expect packets.readAudioPacket(track, block, &actual)
            Swag.require(Slice.equals(packet.bytes, expected.toSlice()), "concurrent mux must retain each AAC access unit")
        }

        Swag.require(expect encoder.finish(&expected))
        Swag.require(Slice.equals((expect packets.readAudioPacket(track, 32, &actual)).bytes, expected.toSlice()))
    }
}
