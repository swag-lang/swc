#global export

// Swaps the values of two variables.
// Takes pointers to the two values to be swapped.
// A pure storage exchange: the values are relocated (`#relocate` applies `opPostMove`, so types with a
// self-referential fixup like the small-string optimization stay valid). After the final relocation,
// the scratch slot is no longer a live `T`; its raw storage is zeroed only to suppress a duplicate drop.
#[Swag.Inline]
func(T) swap(x, y: *T)
{
    var tmp: T = undefined
    tmp = #relocate x[]
    x[] = #relocate y[]
    y[] = #relocate tmp
    Swag.memset(cast([*] void) &tmp, 0, #sizeof(T))
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
