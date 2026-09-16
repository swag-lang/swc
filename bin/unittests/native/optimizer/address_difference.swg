#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func forward(a: u64)->u64 => (a + 7) - a
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func backward(a: u64)->u64 => a - (a + 7)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func negative(a: u64)->u64 => (a - 7) - a
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func narrow(a: u32)->u32 => (a + 7) - a
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shared(a: u64)->u64
{
    let plus = a + 7
    return (plus - a) ^ plus
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func changed(a: u64)->u64
{
    var value = a
    let plus  = value + 7
    value += 3
    return plus - value
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func cancelled(a, b: u64)->u64 => a * (b + 1) - a * b

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 7, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        Swag.assert(forward(a) == 7)
        Swag.assert(backward(a) == 0xFFFFFFFFFFFFFFF9)
        Swag.assert(negative(a) == 0xFFFFFFFFFFFFFFF9)
        Swag.assert(narrow(cast(u32) (a & 0xFFFFFFFF)) == 7)
        Swag.assert(shared(a) == (7'u64 ^ (a + 7)))
        Swag.assert(changed(a) == 4)
        for b in values do Swag.assert(cancelled(a, b) == a)
    }
}
