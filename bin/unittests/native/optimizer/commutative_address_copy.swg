#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func clear(a: u64)->u64 => a & (a - 1)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func clear32(a: u32)->u32 => a & (a - 1)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func unionPrevious(a: u64)->u64 => a | (a - 1)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func xorOffset(a: u64)->u64 => a ^ (a + 7)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func sumOffset(a: u64)->u64 => a + (a - 7)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func productOffset(a: u64)->u64 => a * (a + 7)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func other(a, b: u64)->u64 => a & (b - 1)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shared(a, b: u64)->u64
{
    let previous = a - 1
    let result   = a & previous
    if b != 0 do return result ^ previous
    return result ^ a
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func compared(a: u64)->bool => (a & (a - 1)) == 0

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 2, 7, 8, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        let previous = a - 1
        let expected = a & previous
        Swag.require(clear(a) == expected)
        Swag.require(clear32(cast(u32, (a & 0xFFFFFFFF))) == cast(u32, (expected & 0xFFFFFFFF)))
        Swag.require(unionPrevious(a) == (a | previous))
        Swag.require(xorOffset(a) == (a ^ (a + 7)))
        Swag.require(sumOffset(a) == a + (a - 7))
        Swag.require(productOffset(a) == a * (a + 7))
        Swag.require(compared(a) == (expected == 0))
        for b in values
        {
            Swag.require(other(a, b) == (a & (b - 1)))
            Swag.require(shared(a, b) == (b != 0 ? expected ^ previous : expected ^ a))
        }
    }
}
