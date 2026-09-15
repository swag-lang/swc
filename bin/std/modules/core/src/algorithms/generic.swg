#global export

// Swaps the values of two variables.
// Takes pointers to the two values to be swapped.
// Relocation applies `opPostMove`, so self-referential values stay valid. The
// scratch value's lifetime ends at its final relocation.
#[Swag.Inline]
func(T) swap(x, y: *T)
{
    var tmp: T
    tmp = #relocate x[]
    x[] = #relocate y[]
    y[] = #relocate tmp
}

// Ensures that the first value is less than or equal to the second value.
// If the first value is greater than the second, their contents are swapped.
#[Swag.Inline]
func(T) orderMinMax(x, y: *T)
{
    if x[] > y[] do
        swap(x, y)
}

// Ensures that the first value is greater than or equal to the second value.
// If the first value is less than the second, their contents are swapped.
#[Swag.Inline]
func(T) orderMaxMin(x, y: *T)
{
    if x[] < y[] do
        swap(x, y)
}
