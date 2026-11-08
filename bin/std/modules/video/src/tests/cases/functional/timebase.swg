#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core.Errors

// Absolute clock conversion stays exact at four hours and rounds AAC cut boundaries once.
#test
{
    let video = expect Timebase.create(90_000)
    let audio = expect Timebase.create(44_100)
    Swag.require(video.ticksPerSecond() == 90_000)
    Swag.require(expect video.convertFrom(4'u64 * 60 * 60 * 1_000_000_000, 1_000_000_000) == 1_296_000_000)
    Swag.require(expect audio.convertFrom(1_536, 12_800) == 5_292)
    Swag.require(expect audio.convertFrom(3_072, 12_800) == 10_584)
    let oneTick = expect Timebase.create(1)
    Swag.require(expect oneTick.convertFrom(499_999_999, 1_000_000_000) == 0)
    Swag.require(expect oneTick.convertFrom(500_000_000, 1_000_000_000) == 1)
}

// Invalid rates and a converted value beyond u64 fail without wrapping.
#test
{
    var rejected: Swag.Error
    discard catch Timebase.create(0) as rejected
    Swag.require(rejected.value() is BadParameterError)
    let clock = expect Timebase.create(90_000)
    discard catch clock.convertFrom(1, 0) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch clock.convertFrom(Swag.U64.Max, 1) as rejected
    Swag.require(rejected.value() is OverflowError)
}
