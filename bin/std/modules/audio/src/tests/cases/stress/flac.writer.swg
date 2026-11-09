#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Ten minutes of stereo silence use a fixed input block and remain resumable.
#[Swag.TestTag("stress")]
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("audio-flac-stress-%.flac", Guid128.random()))
    defer discard catch File.delete(path)
    const Frames = 10'u64 * 60 * 48_000
    const BlockFrames = 4_096'u64
    var zeros: [BlockFrames * 2] s16

    var writer = expect Flac.Writer.create(path.toString(), 2, 48_000)
    for index in Frames / BlockFrames
    {
        expect writer.addFrames(Swag.makeSlice(&zeros[0], zeros.count))
        if (index + 1) % 512 == 0 do
            expect writer.flush()
    }
    expect writer.addFrames(Swag.makeSlice(&zeros[0], (Frames % BlockFrames) * 2))
    expect writer.end()
    Swag.require(writer.sampleFrameCount() == Frames)
    Swag.require(writer.writtenByteCount() < 1_000_000)

    var resumed = expect Flac.Writer.resume(path.toString())
    Swag.require(resumed.sampleFrameCount() == Frames)
    expect resumed.end()
    let sound = expect SoundFile.load(path.toString(), preloadData: false)
    Swag.require(sound.sampleFrameCount() == Frames)
    Swag.require(sound.packetCount() == (Frames + BlockFrames - 1) / BlockFrames)
}
