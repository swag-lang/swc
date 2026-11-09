#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Audio, Pixel

// Runs two seconds of software BGRA conversion, H.264, AAC and fragmented MP4 at 1080p60.
#[Swag.TestTag("stress")]
#test
{
    let path = videoTempPath("mp4-software-1080p60", "mp4")
    defer discard catch File.delete(path)

    let image = Image.create(1920, 1080, .BGRA8)
    Memory.set(image.pixels.storage(), 127, image.pixels.count)
    var nv12: Nv12Frame
    var video = expect H264.Encoder.create(1920, 1080, keyInterval: 120)
    var audio = expect Aac.Encoder.create(48_000, 2)
    var writer = expect Mp4.FragmentedWriter.createWithAudio(path, 1920, 1080, 90_000,
                                                             video.decoderConfig(),
                                                             Mp4.FragmentedAudioConfig{48_000, 2,
                                                                                       audio.decoderConfig()})
    var watch: Time.Stopwatch
    watch.start()
    var audioBlock = 0'u64
    for frame in 120'u64
    {
        expect nv12.convertFrom(&image)
        expect writer.addPacket(expect video.encode(&nv12, frame * 1_500, 1_500))
        while audioBlock < 94 and audioBlock * 1_024 < (frame + 1) * 800
        {
            var samples: [2 * 1_024] s16
            for index in 1_024'u64
            {
                let sample = audioBlock * 1_024 + index
                samples[index * 2] = cast(s16, Math.round(8_000.0 *
                    Math.sin(Math.ConstF64.TwoPi * 1_000.0 * sample / 48_000.0)))
                samples[index * 2 + 1] = cast(s16, Math.round(6_000.0 *
                    Math.sin(Math.ConstF64.TwoPi * 1_500.0 * sample / 48_000.0)))
            }
            var packet: Array'u8
            expect audio.encode(Swag.makeSlice(&samples[0], samples.count), &packet)
            expect writer.addAudioPacket(EncodedPacket{packet.toSlice(), audioBlock * 1_024,
                                                       audioBlock * 1_024, 1_024, true})
            audioBlock += 1
        }
    }
    expect writer.end()
    watch.stop()
    Console.printf("Software MP4 1080p60: % us for 120 video and % audio packets\n",
                   watch.elapsedMicroseconds(), audioBlock)

    let summary = expect Mp4.summarizeFragmentedRecording(path)
    Swag.require(summary.video.packetCount == 120 and summary.audioTracks.count == 1)
    Swag.require(summary.audioTracks[0].packetCount == 94 and not summary.hasIncompleteTail)

    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 120 and reader.audioTrackCount() == 1)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 119)
    Swag.require(Slice.equals(decoded.luma.toSlice(), nv12.luma()))
    let uv = nv12.chroma()
    for index in decoded.chromaB.count
    {
        Swag.require(decoded.chromaB[index] == uv[index * 2])
        Swag.require(decoded.chromaR[index] == uv[index * 2 + 1])
    }
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleEncoding() == .AacLc and sound.sampleFrameCount() == 94 * 1_024)
}

// Measures the same pipeline while alternating two textured pictures shifted by 16 pixels.
// Input pictures and PCM are prepared before the clock starts.
#[Swag.TestTag("stress")]
#test
{
    let path = videoTempPath("mp4-software-scroll-1080p60", "mp4")
    defer discard catch File.delete(path)
    let first = Image.create(1920, 1080, .BGRA8)
    let moved = Image.create(1920, 1080, .BGRA8)
    let firstPixels = first.pixels.storage()
    let movedPixels = moved.pixels.storage()
    for y in 1080
    {
        for x in 1920
        {
            let offset = cast(u64, (y * 1920 + x) * 4)
            let movedY = (y + 16) % 1080
            firstPixels[offset]     = cast(u8, (x * 7 + y * 3) & 255)
            firstPixels[offset + 1] = cast(u8, (x * 5 + y * 11) & 255)
            firstPixels[offset + 2] = cast(u8, (x * 13 + y * 2) & 255)
            firstPixels[offset + 3] = 255
            movedPixels[offset]     = cast(u8, (x * 7 + movedY * 3) & 255)
            movedPixels[offset + 1] = cast(u8, (x * 5 + movedY * 11) & 255)
            movedPixels[offset + 2] = cast(u8, (x * 13 + movedY * 2) & 255)
            movedPixels[offset + 3] = 255
        }
    }
    var samples: [2 * 1_024] s16
    for index in 1_024'u64
    {
        samples[index * 2] = cast(s16, Math.round(8_000.0 *
            Math.sin(Math.ConstF64.TwoPi * 1_000.0 * index / 48_000.0)))
        samples[index * 2 + 1] = cast(s16, Math.round(6_000.0 *
            Math.sin(Math.ConstF64.TwoPi * 1_500.0 * index / 48_000.0)))
    }

    var nv12: Nv12Frame
    var video = expect H264.Encoder.create(1920, 1080, keyInterval: 120)
    var audio = expect Aac.Encoder.create(48_000, 2)
    var writer = expect Mp4.FragmentedWriter.createWithAudio(path, 1920, 1080, 90_000,
                                                             video.decoderConfig(),
                                                             Mp4.FragmentedAudioConfig{48_000, 2,
                                                                                       audio.decoderConfig()})
    var watch: Time.Stopwatch
    watch.start()
    var audioBlock = 0'u64
    for frame in 120'u64
    {
        if frame % 2 do
            expect nv12.convertFrom(&moved)
        else do
            expect nv12.convertFrom(&first)
        let packet = expect video.encode(&nv12, frame * 1_500, 1_500)
        if frame > 0 do
            Swag.require(packet.bytes.count < 250_000)
        expect writer.addPacket(packet)
        while audioBlock < 94 and audioBlock * 1_024 < (frame + 1) * 800
        {
            var encoded: Array'u8
            expect audio.encode(Swag.makeSlice(&samples[0], samples.count), &encoded)
            expect writer.addAudioPacket(EncodedPacket{encoded.toSlice(), audioBlock * 1_024,
                                                       audioBlock * 1_024, 1_024, true})
            audioBlock += 1
        }
    }
    expect writer.end()
    watch.stop()
    Console.printf("Software MP4 scrolling 1080p60: % us for 120 video and % audio packets\n",
                   watch.elapsedMicroseconds(), audioBlock)

    let summary = expect Mp4.summarizeFragmentedRecording(path)
    Swag.require(summary.video.packetCount == 120 and summary.audioTracks.count == 1)
    Swag.require(summary.audioTracks[0].packetCount == 94 and not summary.hasIncompleteTail)
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 120 and reader.audioTrackCount() == 1)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 119)
    Swag.require(Slice.equals(decoded.luma.toSlice(), nv12.luma()))
    let uv = nv12.chroma()
    for index in decoded.chromaB.count
    {
        Swag.require(decoded.chromaB[index] == uv[index * 2])
        Swag.require(decoded.chromaR[index] == uv[index * 2 + 1])
    }
}
