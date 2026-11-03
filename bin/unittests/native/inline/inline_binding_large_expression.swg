#global private

#[Swag.Inline]
func retain(value: s32)->s32 => value

#[Swag.NoInline]
func calculate(value: s32)->s32
{
    // Keep the binding larger than the inline validator's small visited set.
    return retain(
        value + value + value + value + value + value + value + value +
        value + value + value + value + value + value + value + value +
        value + value + value + value + value + value + value + value +
        value + value + value + value + value + value + value + value)
}

#test
{
    Swag.require(calculate(3) == 96)
    Swag.require(calculate(-2) == -64)
}
