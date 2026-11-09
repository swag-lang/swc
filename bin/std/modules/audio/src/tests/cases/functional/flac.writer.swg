#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

func flacWriterPath(label: string)->String
    => Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("audio-flac-%-%.flac", label, Guid128.random()))

func assertFlacWriterSamples(path: string, expected: const [..] s16, channels, sampleRate: u32)
{
    let sound = expect SoundFile.load(path, preloadData: false)
    Swag.require(sound.sampleEncoding() == .Flac)
    Swag.require(sound.numChannels() == channels and sound.sampleRateHz() == sampleRate)
    Swag.require(sound.sampleFrameCount() == expected.count / channels)
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(Slice.equals(decoded.toSlice(), expected))
}

// Every channel count the decoder supports survives split input and a flushed playable prefix.
#test
{
    for channels in [1'u16, 2, 6, 8]
    {
        let path = flacWriterPath("channels")
        defer discard catch File.delete(path)
        var writer = expect Flac.Writer.create(path.toString(), channels, 48_000)
        var samples: Array's16
        for frame in 9_000
        {
            let value = cast(s16, cast(s32, frame % 401) - 200)
            for channel in channels do
                samples.add(value + cast(s16, channel * 3))
        }

        let first = 4_100'u64 * channels
        expect writer.addFrames(samples.toSlice()[until first])
        Swag.require(writer.sampleFrameCount() == 4_100)
        expect writer.flush()
        assertFlacWriterSamples(path.toString(), samples.toSlice()[until first], channels, 48_000)

        expect writer.addFrames(samples.toSlice()[first until samples.count])
        expect writer.end()
        expect writer.end()
        Swag.require(writer.sampleFrameCount() == 9_000)
        Swag.require(writer.writtenByteCount() == (expect File.info(path)).size)
        assertFlacWriterSamples(path.toString(), samples.toSlice(), channels, 48_000)
    }
}

// Silence and smooth ramps choose compact subframes; irregular noise stays verbatim.
#test
{
    for pattern in 3
    {
        let path = flacWriterPath("modes")
        defer discard catch File.delete(path)
        var writer = expect Flac.Writer.create(path.toString(), 1, 44_100)
        var samples: Array's16
        for index in 4_096
        {
            let value = pattern == 0 ? Swag.S16.Min :
                        (pattern == 1 ? cast(s16, cast(s32, index) - 2_048) :
                         cast #bit(s16, cast(u16, (cast(u32, index) * 17_323 + 9_137) & 0xFFFF)))
            samples.add(value)
        }
        expect writer.addFrames(samples.toSlice())
        expect writer.end()
        assertFlacWriterSamples(path.toString(), samples.toSlice(), 1, 44_100)

        let file = expect File.readAllBytes(path)
        let kind = file[66]
        Swag.require(kind == (pattern == 0 ? 0'u8 : (pattern == 1 ? 0x12'u8 : 0x02'u8)))
        if pattern < 2 do
            Swag.require(file.count < samples.count * 2 / 4)
    }
}

// Invalid configuration and incomplete sample frames fail before the writer advances.
#test
{
    let path = flacWriterPath("invalid")
    defer discard catch File.delete(path)
    var rejected: Swag.Error
    discard catch Flac.Writer.create(path.toString(), 0, 48_000) as rejected
    Swag.require(rejected.value() is BadParameterError and not File.exists(path))
    discard catch Flac.Writer.create(path.toString(), 9, 48_000) as rejected
    Swag.require(rejected.value() is BadParameterError and not File.exists(path))
    discard catch Flac.Writer.create(path.toString(), 1, 0x10_0000) as rejected
    Swag.require(rejected.value() is BadParameterError and not File.exists(path))

    var writer = expect Flac.Writer.create(path.toString(), 2, 48_000)
    const Partial: [3] s16 = [Swag.S16.Min, 0, Swag.S16.Max]
    discard catch writer.addFrames(Swag.makeSlice(&Partial[0], 3)) as rejected
    Swag.require(rejected.value() is BadParameterError)
    Swag.require(writer.sampleFrameCount() == 0 and writer.writtenByteCount() == 58)
    expect writer.addFrames(Swag.makeSlice(&Partial[0], 2))
    expect writer.end()
    discard catch writer.addFrames(Swag.makeSlice(&Partial[0], 2)) as rejected
    Swag.require(rejected.value() is BadParameterError)
    assertFlacWriterSamples(path.toString(), Swag.makeSlice(&Partial[0], 2), 2, 48_000)
}

// Streaming chunk boundaries do not change FLAC frames or the PCM checksum.
#test
{
    let wholePath = flacWriterPath("whole")
    let splitPath = flacWriterPath("split")
    defer discard catch File.delete(wholePath)
    defer discard catch File.delete(splitPath)
    var samples: Array's16
    for index in 8_193
    {
        let value = cast(s16, cast(s32, index % 1_001) - 500)
        samples.add(value)
        samples.add(-value)
    }

    var whole = expect Flac.Writer.create(wholePath.toString(), 2, 48_000)
    expect whole.addFrames(samples.toSlice())
    expect whole.end()

    var split = expect Flac.Writer.create(splitPath.toString(), 2, 48_000)
    expect split.addFrames([])
    var frame = 0'u64
    while frame < 8_193
    {
        let next = Math.min(frame + 1 + frame % 257, 8_193'u64)
        expect split.addFrames(samples.toSlice()[frame * 2 until next * 2])
        frame = next
    }
    expect split.end()

    let wholeBytes = expect File.readAllBytes(wholePath)
    let splitBytes = expect File.readAllBytes(splitPath)
    Swag.require(Slice.equals(wholeBytes.toSlice(), splitBytes.toSlice()))
    assertFlacWriterSamples(splitPath.toString(), samples.toSlice(), 2, 48_000)
}

// A one-sample final block and a long sample index retain the exact length and order.
#test
{
    let path = flacWriterPath("boundaries")
    defer discard catch File.delete(path)
    var writer = expect Flac.Writer.create(path.toString(), 1, 48_000)
    var samples: Array's16
    for index in 70_000 do
        samples.add(cast(s16, cast(s32, index % 7) - 3))
    expect writer.addFrames(samples.toSlice())
    expect writer.end()
    let sound = expect SoundFile.load(path.toString(), preloadData: false)
    Swag.require(sound.packetCount() == 18)
    Swag.require((expect sound.packet(17)).sampleFrameCount == 368)
    assertFlacWriterSamples(path.toString(), samples.toSlice(), 1, 48_000)

    let single = flacWriterPath("single")
    defer discard catch File.delete(single)
    var one = expect Flac.Writer.create(single.toString(), 1, 48_000)
    const Last: [1] s16 = [Swag.S16.Min]
    expect one.addFrames(Swag.makeSlice(&Last[0], 1))
    expect one.end()
    assertFlacWriterSamples(single.toString(), Swag.makeSlice(&Last[0], 1), 1, 48_000)
}

// Resume validates the committed prefix, discards an incomplete tail, and continues its MD5.
#test
{
    let path = flacWriterPath("resume")
    defer discard catch File.delete(path)
    var samples: Array's16
    for index in 5_000 do
        samples.add(cast(s16, cast(s32, index % 301) - 150))
    var committedSize = 0'u64
    scope
    {
        var writer = expect Flac.Writer.create(path.toString(), 1, 48_000)
        expect writer.addFrames(samples.toSlice()[until 4_196])
        expect writer.flush()
        committedSize = writer.writtenByteCount()
        expect writer.addFrames(samples.toSlice()[4_196 until 4_300])
    }
    var tail = expect ByteSink.openAppendFile(path.toString())
    expect tail.writeText("incomplete frame")
    expect tail.close()
    Swag.require((expect File.info(path)).size > committedSize)
    assertFlacWriterSamples(path.toString(), samples.toSlice()[until 4_196], 1, 48_000)

    var writer = expect Flac.Writer.resume(path.toString())
    Swag.require(writer.sampleFrameCount() == 4_196 and writer.writtenByteCount() == committedSize)
    expect writer.addFrames(samples.toSlice()[4_196 until samples.count])
    expect writer.end()
    assertFlacWriterSamples(path.toString(), samples.toSlice(), 1, 48_000)

    var complete = expect Flac.Writer.resume(path.toString())
    Swag.require(complete.sampleFrameCount() == 5_000)
    expect complete.end()
    assertFlacWriterSamples(path.toString(), samples.toSlice(), 1, 48_000)
}

// Corruption in the committed FLAC frames fails before resume alters the source file.
#test
{
    let path = flacWriterPath("corrupt")
    defer discard catch File.delete(path)
    var writer = expect Flac.Writer.create(path.toString(), 1, 48_000)
    const Samples: [4] s16 = [4, 5, 6, 7]
    expect writer.addFrames(Swag.makeSlice(&Samples[0], Samples.count))
    expect writer.end()
    let original = expect File.readAllBytes(path)
    var changed = original
    changed[changed.count - 3] ^= 1
    discard expect File.writeAllBytes(path, changed.toSlice())
    var rejected: Swag.Error
    discard catch Flac.Writer.resume(path.toString()) as rejected
    Swag.require(rejected.value() is InvalidFormatError)
    Swag.require((expect File.readAllBytes(path)).count == changed.count)

    changed = original
    changed[50] = 0xFF
    discard expect File.writeAllBytes(path, changed.toSlice())
    discard catch Flac.Writer.resume(path.toString()) as rejected
    Swag.require(rejected.value() is InvalidFormatError)
    Swag.require((expect File.info(path)).size == changed.count)

    changed = original
    changed[26] ^= 1
    discard expect File.writeAllBytes(path, changed.toSlice())
    discard catch Flac.Writer.resume(path.toString()) as rejected
    Swag.require(rejected.value() is InvalidFormatError)
    Swag.require((expect File.info(path)).size == changed.count)

    changed = original
    changed[25] ^= 1
    discard expect File.writeAllBytes(path, changed.toSlice())
    discard catch Flac.Writer.resume(path.toString()) as rejected
    Swag.require(rejected.value() is InvalidFormatError)
    Swag.require((expect File.info(path)).size == changed.count)
}

// Empty files carry a legal FLAC prologue, even though SoundFile requires one packet to play.
#test
{
    let path = flacWriterPath("empty")
    defer discard catch File.delete(path)
    var writer = expect Flac.Writer.create(path.toString(), 2, 48_000)
    expect writer.end()
    expect writer.end()
    let bytes = expect File.readAllBytes(path)
    Swag.require(bytes.count == 58 and Slice.equals(bytes.toSlice()[until 4], "fLaC"))
    Swag.require(bytes[42] == 0x82)
    var resumed = expect Flac.Writer.resume(path.toString())
    Swag.require(resumed.sampleFrameCount() == 0 and resumed.writtenByteCount() == 58)
    const OneFrame: [2] s16 = [100, -100]
    expect resumed.addFrames(Swag.makeSlice(&OneFrame[0], 2))
    expect resumed.end()
    assertFlacWriterSamples(path.toString(), Swag.makeSlice(&OneFrame[0], 2), 2, 48_000)
}
