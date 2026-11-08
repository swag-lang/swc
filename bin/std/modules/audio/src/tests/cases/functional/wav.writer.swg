#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

// Flushed mono and stereo prefixes decode exactly, including the minimum PCM value.
#test
{
    for channels in [1'u16, 2]
    {
        let path = Path.combine(Env.getSpecialDirectory(.Temp),
                                Format.toString("audio-writer-%-%.wav", channels, Guid128.random()))
        defer discard catch File.delete(path)
        var writer = expect Wav.Writer.create(path.toString(), channels, 44_100)
        Swag.require(writer.sampleFrameCount() == 0 and writer.writtenByteCount() == 44)

        const Samples: [4] s16 = [Swag.S16.Min, -1, 0, Swag.S16.Max]
        expect writer.addFrames(Swag.makeSlice(&Samples[0], 2))
        expect writer.flush()
        expect writer.addFrames(Swag.makeSlice(&Samples[2], 2))
        expect writer.flush()
        Swag.require(writer.sampleFrameCount() == 4 / channels and writer.writtenByteCount() == 52)
        expect writer.end()
        expect writer.end()
        let complete = expect SoundFile.load(path.toString(), preloadData: false)
        Swag.require(complete.sampleEncoding() == .Pcm16)
        Swag.require(complete.sampleRateHz() == 44_100 and complete.numChannels() == channels)
        Swag.require(complete.sampleFrameCount() == 4 / channels)
        var decoded: Array's16
        expect complete.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
        {
            decoded.add(part)
            return true
        })
        Swag.require(Slice.equals(decoded.toSlice(), Swag.makeSlice(&Samples[0], 4)))
    }
}

// Dropping a writer after flush leaves the playable prefix without requiring end().
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("audio-writer-stopped-%.wav", Guid128.random()))
    defer discard catch File.delete(path)
    scope
    {
        var writer = expect Wav.Writer.create(path.toString(), 1, 48_000)
    }

    let empty = expect SoundFile.load(path.toString())
    Swag.require(empty.sampleFrameCount() == 0)
    scope
    {
        var writer = expect Wav.Writer.create(path.toString(), 1, 48_000)
        const Prefix: [2] s16 = [123, -456]
        expect writer.addFrames(Swag.makeSlice(&Prefix[0], 2))
        expect writer.flush()
    }

    let stopped = expect SoundFile.load(path.toString())
    Swag.require(stopped.sampleFrameCount() == 2 and stopped.payloadSize() == 4)
}

// Invalid input does not change the file or advance its sample-frame count.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("audio-writer-invalid-%.wav", Guid128.random()))
    defer discard catch File.delete(path)
    var rejected: Swag.Error
    discard catch Wav.Writer.create(path.toString(), 0, 44_100) as rejected
    Swag.require(rejected.value() is BadParameterError)
    Swag.require(not File.exists(path))
    var writer = expect Wav.Writer.create(path.toString(), 2, 48_000)
    const Partial: [3] s16 = [1, 2, 3]
    discard catch writer.addFrames(Swag.makeSlice(&Partial[0], 3)) as rejected
    Swag.require(rejected.value() is BadParameterError)
    Swag.require(writer.sampleFrameCount() == 0 and writer.writtenByteCount() == 44)
    expect writer.end()
    discard catch writer.addFrames(Swag.makeSlice(&Partial[0], 2)) as rejected
    Swag.require(rejected.value() is BadParameterError)
}

// Resume discards unflushed bytes and continues the committed sample-frame count.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("audio-writer-resume-%.wav", Guid128.random()))
    defer discard catch File.delete(path)
    const First: [2] s16 = [100, -100]
    const Lost:  [2] s16 = [300, -300]
    scope
    {
        var writer = expect Wav.Writer.create(path.toString(), 1, 48_000)
        expect writer.addFrames(Swag.makeSlice(&First[0], 2))
        expect writer.flush()
        expect writer.addFrames(Swag.makeSlice(&Lost[0], 2))
    }

    var tail = expect ByteSink.openAppendFile(path.toString())
    expect tail.writeByte(0xAA)
    expect tail.close()
    Swag.require((expect File.info(path)).size == 49)

    var resumed = expect Wav.Writer.resume(path.toString())
    Swag.require(resumed.sampleFrameCount() == 2 and resumed.writtenByteCount() == 48)
    expect resumed.addFrames(Swag.makeSlice(&Lost[0], 1))
    expect resumed.end()
    var complete = expect Wav.Writer.resume(path.toString())
    Swag.require(complete.sampleFrameCount() == 3 and complete.writtenByteCount() == 50)
    expect complete.end()
    let sound = expect SoundFile.load(path.toString())
    Swag.require(sound.sampleFrameCount() == 3)
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(Slice.equals(decoded.toSlice(), [100's16, -100, 300]))
}

// A truncated committed sample fails before resume can alter the source.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("audio-writer-truncated-%.wav", Guid128.random()))
    defer discard catch File.delete(path)
    var writer = expect Wav.Writer.create(path.toString(), 1, 48_000)
    const Samples: [2] s16 = [12, 34]
    expect writer.addFrames(Swag.makeSlice(&Samples[0], 2))
    expect writer.end()
    let complete = expect File.readAllBytes(path)
    discard expect File.writeAllBytes(path, complete.toSlice()[until complete.count - 1])
    var rejected: Swag.Error
    discard catch Wav.Writer.resume(path.toString()) as rejected
    Swag.require(rejected.value() is InvalidFormatError)
    Swag.require((expect File.info(path)).size == complete.count - 1)
}

// Silence spans multiple fixed-size chunks and preserves the samples around the gap.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("audio-writer-silence-%.wav", Guid128.random()))
    defer discard catch File.delete(path)
    var writer = expect Wav.Writer.create(path.toString(), 2, 48_000)
    var rejected: Swag.Error
    discard catch writer.addSilence(Swag.U64.Max) as rejected
    Swag.require(rejected.value() is OverflowError)
    Swag.require(writer.sampleFrameCount() == 0 and writer.writtenByteCount() == 44)
    const First: [2] s16 = [123, -123]
    const Last:  [2] s16 = [456, -456]
    expect writer.addFrames(Swag.makeSlice(&First[0], 2))
    expect writer.addSilence(20_000)
    expect writer.addFrames(Swag.makeSlice(&Last[0], 2))
    expect writer.end()
    Swag.require(writer.sampleFrameCount() == 20_002)
    let sound = expect SoundFile.load(path.toString(), preloadData: false)
    Swag.require(sound.sampleFrameCount() == 20_002 and sound.payloadSize() == 80_008)
    let start = expect sound.readPayload(0, 8)
    Swag.require(Slice.equals(start.toSlice(), [123'u8, 0, 133, 255, 0, 0, 0, 0]))
    let middle = expect sound.readPayload(32 * 1024, 16)
    for byte in middle do
        Swag.require(byte == 0)
    let end = expect sound.readPayload(80_004, 4)
    Swag.require(Slice.equals(end.toSlice(), [200'u8, 1, 56, 254]))
    discard catch writer.addSilence(0) as rejected
    Swag.require(rejected.value() is BadParameterError)
}
