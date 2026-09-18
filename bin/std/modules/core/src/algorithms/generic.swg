#global export

// Swaps the values that `x` and `y` point to.
//
// The values are relocated rather than copied. Relocation applies `opPostMove`, so
// self-referential values stay valid, and the scratch value's lifetime ends at its final
// relocation.
#[Swag.Inline]
func(T) swap(x, y: *T)
{
    var tmp: T
    tmp = #relocate x[]
    x[] = #relocate y[]
    y[] = #relocate tmp
}

// Swaps the values that `x` and `y` point to when `x` is greater, so that `x` holds the smaller one.
#[Swag.Inline]
func(T) orderMinMax(x, y: *T)
{
    if x[] > y[] do
        swap(x, y)
}

// Swaps the values that `x` and `y` point to when `x` is smaller, so that `x` holds the greater one.
#[Swag.Inline]
func(T) orderMaxMin(x, y: *T)
{
    if x[] < y[] do
        swap(x, y)
}
