#global private

struct InlineMillisecondsDuration
{
    seconds: f64
}

#[Swag.Inline]
func inlineDurationFromMilliseconds(value: u64)->InlineMillisecondsDuration => InlineMillisecondsDuration{value / 1000.0}

var InlineMillisecondsRuntimeValue = 250'u32

#test
{
    // The inline parameter is u64, while its call-site expression is u32. The division still
    // belongs to the f64 result selected in the provider; lowering it as an integer operation
    // would encode an invalid integer opcode over float registers.
    let duration = inlineDurationFromMilliseconds(InlineMillisecondsRuntimeValue)
    Swag.assert(duration.seconds == 0.25)
}
