#global fileprivate
/**
# User-Defined Literals

User-defined literals extend literal meaning so custom types can be initialized
directly with unit-like suffixes (e.g., '4'ms'). This example defines a 'Duration'
type that stores seconds and accepts seconds, milliseconds, minutes, and hours.

# Literal Suffixes
A literal suffix immediately follows a numeric literal to indicate a unit or type,
e.g., `4'ms` means 4 milliseconds.

To support user-defined literals, provide:
1) a type (e.g., 'Duration'), and
2) methods to convert the numeric value according to the suffix.
*/

// Represents a delay, expressed in seconds.
struct Duration
{
    timeInSeconds: f32
}

/**
Use the operator overload hook 'opSetLiteral' to convert a value plus suffix.
*/
impl Duration
{
    // Handle literals like '5's', '500'ms', '2'min', '1'h'
    #[Swag.ConstExpr, Swag.Implicit, Swag.Inline]
    mtd(suffix: string) opSetLiteral(value: s32)
    {
        #if suffix == "s" do
            me.timeInSeconds = value
        #elif suffix == "ms" do
            me.timeInSeconds = value / 1000.0
        #elif suffix == "min" do
            me.timeInSeconds = value * 60.0
        #elif suffix == "h" do
            me.timeInSeconds = value * 3600.0
        #else do
            #error("invalid duration literal suffix '" ++ suffix ++ "'")
    }
}

/**
You can then place the suffix right after the numeric literal when the type is 'Duration'.
*/

func toto(x: Duration) {}

#test
{
    let delaySeconds: Duration      = 5's
    let delayMilliseconds: Duration = 500'ms
    let delayMinutes: Duration      = 2'min
    let delayHours: Duration        = 1'h

    @assert(delaySeconds.timeInSeconds == 5.0)
    @assert(delayMilliseconds.timeInSeconds == 0.5)
    @assert(delayMinutes.timeInSeconds == 120.0)
    @assert(delayHours.timeInSeconds == 3600.0)

    // Use the 'Duration' type in functions
    toto(5'ms)
    toto(1'h)
}
