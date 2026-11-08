#global public

using Core.Errors

// Describes an integer media clock in ticks per second.
//
// Convert absolute timestamps, then subtract adjacent results for packet durations. Converting
// each duration separately can accumulate rounding error over a long recording.
#[Swag.Opaque]
struct Timebase
{
    internal ticksPerSecondValue: u32
}

impl Timebase
{
    // Creates a media clock with a positive number of ticks per second.
    func create(ticksPerSecond: u32)->Timebase fail
    {
        if not ticksPerSecond do
            fail BadParameterError{"media timebase needs a positive tick rate"}
        return Timebase{ticksPerSecond}
    }

    // Returns the clock's tick rate.
    mtd const ticksPerSecond()->u32 => .ticksPerSecondValue

    // Rounds an absolute timestamp from another clock to this clock's nearest tick.
    //
    // Midpoints round upward. The source clock must have a positive tick rate. The calculation
    // splits whole seconds from the remainder, so long nanosecond timestamps do not overflow
    // before conversion to a video or audio clock.
    mtd const convertFrom(timestamp: u64, sourceTicksPerSecond: u32)->u64 fail
    {
        if not .ticksPerSecondValue or not sourceTicksPerSecond do
            fail BadParameterError{"media timebase conversion needs positive tick rates"}
        let wholeSeconds = timestamp / sourceTicksPerSecond
        let remainder    = timestamp % sourceTicksPerSecond
        if wholeSeconds > Swag.U64.Max / .ticksPerSecondValue do
            fail OverflowError{"media timestamp conversion overflows"}
        let wholeTicks = wholeSeconds * .ticksPerSecondValue
        let fraction   = remainder * .ticksPerSecondValue
        let rounded    = fraction / sourceTicksPerSecond +
                         cast(u64, fraction % sourceTicksPerSecond >= (cast(u64, sourceTicksPerSecond) + 1) / 2)
        if rounded > Swag.U64.Max - wholeTicks do
            fail OverflowError{"media timestamp conversion overflows"}
        return wholeTicks + rounded
    }
}
