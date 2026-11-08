#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core.Errors

// Fractional frame rates stay on one exact clock over four hours without duration drift.
#test
{
    let rate  = expect FrameRate.create(30_000, 1_001)
    var pacer = expect FramePacer.create(rate, 1_000_000_000, 90_000)
    const Start = 1_000_000_000_000'u64
    var slot: FrameSlot
    Swag.require(expect pacer.tryAccept(Start, &slot))
    Swag.require(slot.index == 0 and slot.decodeTime == 0 and slot.duration == 3003)
    Swag.require(slot.skippedFrames == 0)
    Swag.require(not expect pacer.tryAccept(Start + 33_366_666, &slot))
    Swag.require(slot.index == 0)
    Swag.require(expect pacer.tryAccept(Start + 33_366_667, &slot))
    Swag.require(slot.index == 1 and slot.decodeTime == 3003 and slot.duration == 3003)
    Swag.require(expect pacer.tryAccept(Start + 100_100_000, &slot))
    Swag.require(slot.index == 3 and slot.decodeTime == 9009 and slot.skippedFrames == 1)
    Swag.require(expect pacer.tryAccept(Start + 4'u64 * 60 * 60 * 1_000_000_000, &slot))
    Swag.require(slot.index == 431_568 and slot.decodeTime == slot.index * 3003)
    Swag.require(slot.duration == 3003 and slot.skippedFrames == 431_564)
}

// Integer clock ticks alternate frame durations while late pictures report skipped slots.
#test
{
    var pacer = expect FramePacer.create(expect FrameRate.create(60, 1), 1000, 1000)
    var slot: FrameSlot
    Swag.require(expect pacer.tryAccept(10_000, &slot))
    Swag.require(slot.duration == 17)
    Swag.require(expect pacer.tryAccept(10_017, &slot))
    Swag.require(slot.index == 1 and slot.decodeTime == 17 and slot.duration == 16)
    Swag.require(expect pacer.tryAccept(10_034, &slot))
    Swag.require(slot.index == 2 and slot.decodeTime == 33 and slot.duration == 17)
    Swag.require(expect pacer.tryAccept(10_100, &slot))
    Swag.require(slot.index == 6 and slot.decodeTime == 100 and slot.skippedFrames == 3)
}

// Invalid clocks and a backwards timestamp leave the accepted position intact.
#test
{
    let rate = expect FrameRate.create(60, 1)
    var rejected: Swag.Error
    discard catch FramePacer.create(rate, 0, 90_000) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch FramePacer.create(rate, 1_000_000_000, 30) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch FramePacer.create(expect FrameRate.create(1, Swag.U32.Max), 1, Swag.U32.Max) as rejected
    Swag.require(rejected.value() is BadParameterError)

    var pacer = expect FramePacer.create(rate, 1_000, 90_000)
    var slot: FrameSlot
    Swag.require(expect pacer.tryAccept(0, &slot))
    discard catch pacer.tryAccept(Swag.U64.Max, &slot) as rejected
    Swag.require(rejected.value() is OverflowError)
    Swag.require(expect pacer.tryAccept(17, &slot))
    Swag.require(slot.index == 1 and slot.decodeTime == 1500)
    discard catch pacer.tryAccept(16, &slot) as rejected
    Swag.require(rejected.value() is BadParameterError)
}
