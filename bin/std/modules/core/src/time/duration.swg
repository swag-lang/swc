#global public
#global namespace Time

using Swag

// Represents a delay, expressed in seconds.
struct Duration
{
    timeInSeconds: f32     // The duration in seconds
}

impl Duration
{
    #[ConstExpr, Implicit, Inline]
    mtd opSet(valueMs: s32)
    {
        .timeInSeconds = valueMs / 1000.0
    }

    #[ConstExpr, Implicit, Inline]
    mtd(suffix: string) opSetLiteral(value: s32)
    {
        #static switch suffix
        {
        case "s":   .timeInSeconds = value
        case "ms":  .timeInSeconds = value / 1000.0
        case "min": .timeInSeconds = value * 60.0
        case "h":   .timeInSeconds = value * 3600.0
        default:    #error("invalid duration literal suffix '" ++ suffix ++ "'")
        }
    }

    #[Inline]
    {
        // Returns the value in milliseconds
        mtd const toMs()->u32 => cast(u32) Math.round(.timeInSeconds * 1000)

        // Returns a duration initialized with milliseconds
        func fromMs(valueMs: u32)->Duration => Duration{valueMs / 1000.0}
    }
}
