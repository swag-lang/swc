#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func twice64(a: u64)->u64 => a + a

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func twice32(a: u32)->u32 => a + a

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func accumulateTwice(a, b: u64)->u64
{
    var value = a
    value += b
    return value + value
}

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func keepOriginal(a: u64)->u64 => (a + a) ^ a

#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checkedTwice(a: u64)->u64 => a + a

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        Swag.require(twice64(a) == (a << 1))
        Swag.require(keepOriginal(a) == ((a << 1) ^ a))
        let a32 = cast(u32, (a & 0xFFFFFFFF))
        Swag.require(twice32(a32) == (a32 << 1))
        for b in values do
            Swag.require(accumulateTwice(a, b) == ((a + b) << 1))
    }
    Swag.require(checkedTwice(0x7FFFFFFFFFFFFFFF) == 0xFFFFFFFFFFFFFFFE)
}
