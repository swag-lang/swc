#global export

// Swaps the values of two variables.
// Takes pointers to the two values to be swapped.
// A pure storage exchange: the values are raw-moved (`#moveraw` applies `opPostMove`, so types with a
// self-referential fixup like the small-string optimization stay valid). The scratch slot is zeroed at
// the end so its destructor is a no-op (after the last move it shares storage with `*y`).
#[Swag.Inline]
func(T) swap(x, y: *T)
{
    var tmp: T = undefined
    tmp    = #nodrop #moveraw dref x
    dref x = #nodrop #moveraw dref y
    dref y = #nodrop #moveraw tmp
    @memset(cast([*] void) &tmp, 0, #sizeof(T))
}

// Ensures that the first value is less than or equal to the second value.
// If the first value is greater than the second, their contents are swapped.
#[Swag.Inline]
func(T) orderMinMax(x, y: *T)
{
    if dref x > dref y do
        swap(x, y)
}

// Ensures that the first value is greater than or equal to the second value.
// If the first value is less than the second, their contents are swapped.
#[Swag.Inline]
func(T) orderMaxMin(x, y: *T)
{
    if dref x < dref y do
        swap(x, y)
}
