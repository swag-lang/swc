#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Video, Audio

struct LongVideoFixture
{
    const Width           = 160
    const Height          = 96
    const FramesPerSecond = 30'u64
    const Seconds         = 7_200'u64
    const AudioRate       = 48_000'u64
}

impl LongVideoFixture
{
    // Binary minute marks identify the absolute part of the recording; the moving bar and
    // bottom frame marks identify every picture within the two-second closed GOP.
    func picture(minute, frame: u64)->Image
    {
        var result = Image.create(Width, Height, .BGRA8)
        result.fill(Argb.Black)
        let pixels = cast([*] u32, result.pixels.storage())
        for y in 16 until 80
        {
            for x in Width do
                pixels[y * Width + x] = 0xFF202020
            let bar = (frame % 10) * 16
            for x in bar until bar + 16 do
                pixels[y * Width + x] = 0xFFE0E0E0
        }

        for bit in 7'u64
        {
            let color = minute & (1'u64 << bit) ? 0xFFE0E0E0'u32 : 0xFF202020'u32
            for y in 16
            {
                for x in bit * 16 until (bit + 1) * 16 do
                    pixels[y * Width + x] = color
            }
        }

        for bit in 6'u64
        {
            let color = frame & (1'u64 << bit) ? 0xFFE0E0E0'u32 : 0xFF202020'u32
            for y in 80 until Height
            {
                for x in bit * 16 until (bit + 1) * 16 do
                    pixels[y * Width + x] = color
            }
        }

        return result
    }

    func generate(document: String) fail
    {
        let media = Capture.mediaPathOf(document, .Video)
        var video = try H264.Encoder.create(Width, Height)
        var audio = try Aac.StreamEncoder.create(cast(u32, AudioRate), 1, .Voice)
        var signal: [1_024] s16
        for sample in signal.count do
            signal[sample] = cast(s16, Math.round(6_000.0 * Math.sin(Math.ConstF64.TwoPi * 16 * sample / 1024)))
        var packet: Array'u8
        discard try audio.push(signal, &packet)
        var priming: Array'u8
        priming.add(packet.toSlice())
        discard try audio.push(signal, &packet)
        var tone: Array'u8
        tone.add(packet.toSlice())
        var tail: Array'u8
        discard try audio.finish(&tail)

        let configs:   [1] Mp4.FragmentedAudioConfig = [{cast(u32, AudioRate), 1, audio.decoderConfig()}]
        let options     = Mp4.FragmentedOptions{60, 4 * 1024 * 1024, 100, true}
        var writer      = try Mp4.FragmentedWriter.createWithAudioTracks(media, Width, Height, 90_000, video.decoderConfig(), configs, options)
        var nv12:      Nv12Frame
        var audioPacket = 0'u64
        var templates: [60] Array'u8
        for minute in 120'u64
        {
            // Encode one independent two-second pattern per minute, then copy its packets
            // thirty times. Every output frame and AAC packet still has a real timestamp.
            var encoder = try H264.Encoder.create(Width, Height)
            for frame in 60'u64
            {
                let image = picture(minute, frame)
                try nv12.convertFrom(&image)
                let encoded = try encoder.encode(&nv12, frame * 3_000, 3_000)
                templates[frame].clear()
                templates[frame].add(encoded.bytes)
            }

            for frame in 1_800'u64
            {
                let index = minute * 1_800 + frame
                let slot  = frame % 60
                let time  = index * 3_000 + 1_920     // One AAC priming packet precedes picture zero.
                try writer.addPacket({templates[slot].toSlice(), time, time, 3_000, slot == 0})
                while audioPacket * 1_024 < (index + 1) * 1_600
                {
                    let bytes = audioPacket == 0 ? priming.toSlice() : tone.toSlice()
                    try writer.addAudioPacket({bytes, audioPacket * 1_024, audioPacket * 1_024, 1_024, true})
                    audioPacket += 1
                }
            }
        }

        try writer.addAudioPacket({tail.toSlice(), audioPacket * 1_024, audioPacket * 1_024, 1_024, true})
        let counts: [1] u64 = [Seconds * AudioRate]
        try writer.setPresentationEdits(1_920, counts)
        try writer.end()

        var capture: Capture
        capture.file              = document
        capture.title             = "Two-hour video workspace"
        capture.sourceKind        = .Screen
        capture.sourceApplication = "synthetic-fixture"
        capture.sourceWindowTitle = "Two-hour video workspace"
        capture.capturedAt        = {year: 2026, month: 11, day: 10}
        try capture.adoptVideo()
        capture.preview = picture(0, 0)
        capture.changed = true
        try capture.save()
        Console.println("Two-hour fixture: ",
                        document,
                        " media_bytes=",
                        (try File.info(media)).size,
                        " frames=",
                        writer.videoPacketCount(),
                        " audio_packets=",
                        audioPacket + 1)
    }
}

// Deliberate regeneration only: this writes the maintained fixture, not a user's library.
#[Swag.TestTag("integration.capture.fixture")]
#test
{
    Swag.require(Env.hasArgument("capture.fixture.generate=true"),
                 "fixture regeneration requires capture.fixture.generate=true")
    let path = Path.combine(testSourceRoot(), "datas", "video.twohours.scc")
    expect LongVideoFixture.generate(path)
}
