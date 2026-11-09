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

// Small timestamp jitter can be ignored while larger gaps remain visible.
#test
{
    var timeline = expect SampleTimeline.create(1_000, 1_000_000, tolerance: 1)
    discard expect timeline.place(0, 100)
    let early = expect timeline.place(99_000, 100)
    Swag.require(early.startSample == 100 and early.discardedFrames == 0)
    let delayed = expect timeline.place(201_000, 100)
    Swag.require(delayed.startSample == 200 and delayed.silenceFrames == 0)
    let gap = expect timeline.place(304_000, 100)
    Swag.require(gap.startSample == 304 and gap.silenceFrames == 4)
    Swag.require(timeline.sampleEnd() == 404)
}

// An explicit origin leaves the sound offset in the returned silence count.
#test
{
    var timeline = expect SampleTimeline.createWithOrigin(48_000, 1_000_000_000, 1_000_000_000)
    var rejected: Swag.Error
    discard catch timeline.place(999_999_999, 480) as rejected
    Swag.require(rejected.value() is BadParameterError)
    Swag.require(timeline.sampleEnd() == 0)
    let first = expect timeline.place(1_100_000_000, 480)
    Swag.require(first.startSample == 4_800 and first.silenceFrames == 4_800)
    Swag.require(first.discardedFrames == 0 and first.acceptedFrames == 480)
    Swag.require(timeline.sampleEnd() == 5_280)

    var jitter = expect SampleTimeline.createWithOrigin(1_000, 1_000_000, 0, tolerance: 1)
    let offset = expect jitter.place(1_000, 1)
    Swag.require(offset.startSample == 1 and offset.silenceFrames == 1)
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

// A lost input can leave silence through recording stop, even before its first block.
#test
{
    var timeline = expect SampleTimeline.createWithOrigin(48_000, 1_000_000_000, 1_000_000_000)
    Swag.require(expect timeline.advanceTo(1_050_000_000) == 2_400)
    Swag.require(timeline.sampleEnd() == 2_400)
    let resumed = expect timeline.place(1_050_000_000, 480)
    Swag.require(resumed.startSample == 2_400 and resumed.silenceFrames == 0)
    Swag.require(resumed.acceptedFrames == 480)
    Swag.require(expect timeline.advanceTo(1_055_000_000) == 0)
    Swag.require(expect timeline.advanceTo(1_100_000_000) == 1_920)
    Swag.require(expect timeline.advanceTo(1_100_000_000) == 0)
    Swag.require(timeline.sampleEnd() == 4_800)

    var rejected: Swag.Error
    discard catch timeline.advanceTo(1_099_999_999) as rejected
    Swag.require(rejected.value() is BadParameterError and timeline.sampleEnd() == 4_800)
    Swag.require(expect timeline.advanceTo(1_120_000_000) == 960)

    var huge = expect SampleTimeline.createWithOrigin(Swag.U32.Max, 1, 0)
    discard catch huge.advanceTo(Swag.U64.Max) as rejected
    Swag.require(rejected.value() is OverflowError and huge.sampleEnd() == 0)
    Swag.require(expect huge.advanceTo(1) == Swag.U32.Max)

    var implicit = expect SampleTimeline.create(1_000, 1_000)
    Swag.require(expect implicit.advanceTo(10_000) == 0)
    let first = expect implicit.place(10_005, 2)
    Swag.require(first.startSample == 5 and first.silenceFrames == 5)
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
    expect writer.addSilence(expect timeline.advanceTo(9))
    expect writer.end()

    Swag.require(writer.sampleFrameCount() == timeline.sampleEnd())
    let sound = expect SoundFile.load(path.toString())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(Slice.equals(decoded.toSlice(), [10's16, 20, 0, 0, 30, 40, 60, 0, 0]))
}
