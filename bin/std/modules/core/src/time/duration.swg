#global public
#global namespace Time

using Swag

// Represents a non-negative duration in seconds.
struct Duration
{
    readonly seconds: f64     // Duration in seconds.
}

impl Duration
{
    // Creates a duration from an integer literal and its unit suffix.
    #[ConstExpr, Implicit, Inline]
    mtd(suffix: string) opSetLiteral(value: s32)
    {
        Debug.assert(value >= 0)
        #static switch suffix
        {
        case "s":   .seconds = value
        case "ms":  .seconds = value / 1000.0
        case "min": .seconds = value * 60.0
        case "h":   .seconds = value * 3600.0
        default:    #error("invalid duration literal suffix '" ++ suffix ++ "'")
        }
    }

    #[Inline]
    {
        // Returns the duration rounded to the nearest whole millisecond.
        mtd const milliseconds()->u64 => cast(u64) Math.round(.seconds * 1000)

        // Creates a duration from seconds.
        func fromSeconds(value: f64)->Duration
        {
            Debug.assert(value >= 0 and Math.isFinite(value))
            return Duration{value}
        }

        // Creates a duration from milliseconds.
        func fromMilliseconds(value: u64)->Duration => Duration{value / 1000.0}
    }
}
