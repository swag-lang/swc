#global public

using Core, Core.Errors

// Describes an exact number of video frames per second.
//
// The rate is `numerator / denominator`. Both parts are positive and remain
// unchanged, so broadcast rates such as `30000 / 1001` do not lose precision.
#[Swag.Opaque]
struct FrameRate
{
    internal
    {
        numeratorValue:   u32
        denominatorValue: u32
    }
}

impl FrameRate
{
    // Creates an exact positive frame rate.
    //
    // Fails when either part is zero.
    func create(numerator, denominator: u32)->FrameRate fail
    {
        if !numerator or !denominator do
            fail BadParameterError{"frame rate numerator and denominator need positive values"}
        return {numerator, denominator}
    }

    // Returns the rate numerator, in frames.
    mtd const numerator()->u32 => .numeratorValue

    // Returns the rate denominator, in seconds.
    mtd const denominator()->u32 => .denominatorValue

    // Returns the approximate number of frames per second.
    mtd const framesPerSecond()->f64
    {
        if !.denominatorValue do
            return 0
        return cast(f64) .numeratorValue / cast(f64) .denominatorValue
    }

    // Reports whether both parts are positive.
    mtd const isValid()->bool => .numeratorValue != 0 and .denominatorValue != 0
}
