#global private

// Two early returns of -1 and 1 from one comparison select twice from the
// same flags; the optimizer lowers them to the byte difference of two setcc.
// Both orders, signed and unsigned, and a lookalike that compares another
// value must keep their answers.

#[Swag.Optimize(true), Swag.NoInline]
func order(a, b: s32)->s32
{
    if a < b do
        return -1
    if a > b do
        return 1
    return 0
}

#[Swag.Optimize(true), Swag.NoInline]
func orderReversed(a, b: u64)->s64
{
    if a > b do
        return 1
    if a < b do
        return -1
    return 0
}

#[Swag.Optimize(true), Swag.NoInline]
func notOrder(a, b, c: s32)->s32
{
    if a < b do
        return -1
    if a > c do
        return 1
    return 0
}

func reference(less, greater: bool)->s64
{
    if less do
        return -1
    if greater do
        return 1
    return 0
}

#test
{
    let values = [0's64, 1, -1, 2, -2, 0x7FFFFFFF, -0x80000000, 0x7FFFFFFFFFFFFFFF, -0x7FFFFFFFFFFFFFFF - 1]
    for x in values
    {
        for y in values
        {
            let x32 = cast #wrap (s32) x
            let y32 = cast #wrap (s32) y
            Swag.assert(cast(s64) order(x32, y32) == reference(x32 < y32, x32 > y32))
            let ux = cast #bit (u64) x
            let uy = cast #bit (u64) y
            Swag.assert(orderReversed(ux, uy) == reference(ux < uy, ux > uy))
            let z32 = cast #wrap (s32) (x + #wrap 1)
            Swag.assert(cast(s64) notOrder(x32, y32, z32) == reference(x32 < y32, x32 > z32))
        }
    }
}
