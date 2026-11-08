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
