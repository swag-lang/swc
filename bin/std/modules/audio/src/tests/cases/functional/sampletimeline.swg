#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

// Captured blocks can fill a gap, overlap an earlier block, or be entirely old.
#test
{
    var timeline = expect SampleTimeline.create(48_000, 1_000_000_000)
    let first = expect timeline.place(1_000_000_000, 480)
    Swag.require(first.startSample == 0 and first.acceptedFrames == 480)

    let gap = expect timeline.place(1_020_000_000, 480)
    Swag.require(gap.startSample == 960 and gap.silenceFrames == 480)
    Swag.require(gap.discardedFrames == 0 and gap.acceptedFrames == 480)

    let overlap = expect timeline.place(1_025_000_000, 480)
    Swag.require(overlap.startSample == 1440 and overlap.silenceFrames == 0)
    Swag.require(overlap.discardedFrames == 240 and overlap.acceptedFrames == 240)

    let old = expect timeline.place(1_025_000_000, 100)
    Swag.require(old.startSample == 1680 and old.discardedFrames == 100)
    Swag.require(old.acceptedFrames == 0 and timeline.sampleEnd() == 1680)
}

// Fractional sample positions round once, even after ten days of capture.
#test
{
    var timeline = expect SampleTimeline.create(44_100, 1_000_000_000)
    discard expect timeline.place(0, 1)
    let midpoint = expect timeline.place(11_338, 1)
    Swag.require(midpoint.startSample == 1 and midpoint.discardedFrames == 0)
    let distant = expect timeline.place(10'u64 * 24 * 60 * 60 * 1_000_000_000, 441)
    Swag.require(distant.startSample == 38_102_400_000 and distant.silenceFrames == 38_102_399_998)
    Swag.require(timeline.sampleEnd() == 38_102_400_441)
}

// Invalid input and overflows leave the committed sample end intact.
#test
{
    var rejected: Swag.Error
    discard catch SampleTimeline.create(0, 1_000) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch SampleTimeline.create(2, Swag.U64.Max) as rejected
    Swag.require(rejected.value() is BadParameterError)

    var timeline = expect SampleTimeline.create(48_000, 1_000_000_000)
    discard catch timeline.place(0, 0) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard expect timeline.place(100, 1)
    discard catch timeline.place(99, 1) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch timeline.place(100 + 20_834, Swag.U64.Max) as rejected
    Swag.require(rejected.value() is OverflowError)
    Swag.require(timeline.sampleEnd() == 1)
    let next = expect timeline.place(100 + 20_834, 1)
    Swag.require(next.startSample == 1 and next.acceptedFrames == 1)
}

// The placement feeds a streaming WAVE file without retaining captured audio.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("audio-timeline-%.wav", Guid128.random()))
    defer discard catch File.delete(path)
    var timeline = expect SampleTimeline.create(1_000, 1_000)
    var writer   = expect Wav.Writer.create(path.toString(), 1, 1_000)
    const First:  [2] s16 = [10, 20]
    const Second: [2] s16 = [30, 40]
    const Third:  [2] s16 = [50, 60]

    let first = expect timeline.place(0, First.count)
    expect writer.addSilence(first.silenceFrames)
    expect writer.addFrames(Swag.makeSlice(&First[first.discardedFrames], first.acceptedFrames))

    let second = expect timeline.place(4, Second.count)
    expect writer.addSilence(second.silenceFrames)
    expect writer.addFrames(Swag.makeSlice(&Second[second.discardedFrames], second.acceptedFrames))

    let third = expect timeline.place(5, Third.count)
    expect writer.addSilence(third.silenceFrames)
    expect writer.addFrames(Swag.makeSlice(&Third[third.discardedFrames], third.acceptedFrames))
    expect writer.end()

    Swag.require(writer.sampleFrameCount() == timeline.sampleEnd())
    let sound = expect SoundFile.load(path.toString())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(Slice.equals(decoded.toSlice(), [10's16, 20, 0, 0, 30, 40, 60]))
}
