#global private

// A fully unrolled mask chain used to advance one constant per optimizer sweep.
// Keep the conditional count so this exercises the original core bit-test shape.
#[Swag.Optimize(true), Swag.NoInline]
func countBits16(value: u16)->u16
{
    let input = cast(u32) value
    var count = 0'u16
    var mask  = 1'u32
    for 16
    {
        if input & mask do count += 1
        mask <<= 1
    }
    return count
}

#[Swag.Optimize(false), Swag.NoInline]
func countBitsReference(value: u16)->u16
{
    var input = value
    var count = 0'u16
    while input
    {
        count += input & 1
        input >>= 1
    }
    return count
}

#[Swag.Optimize(true), Swag.NoInline]
func countWrapping32(value: u32)->u32
{
    var mask = 0x80000000'u32
    var count = 0'u32
    for 16
    {
        if value & mask do count += 1
        mask <<= 1
    }
    return count
}

#[Swag.Optimize(true), Swag.NoInline]
func countWrapping64(value: u64)->u64
{
    var mask = 0x8000000000000000'u64
    var count = 0'u64
    for 16
    {
        if value & mask do count += 1
        mask <<= 1
    }
    return count
}

#test
{
    for value in 65536 do
        Swag.assert(countBits16(cast(u16) value) == countBitsReference(cast(u16) value))
    Swag.assert(countWrapping32(0xFFFFFFFF) == 1)
    Swag.assert(countWrapping32(0x7FFFFFFF) == 0)
    Swag.assert(countWrapping64(0xFFFFFFFFFFFFFFFF) == 1)
    Swag.assert(countWrapping64(0x7FFFFFFFFFFFFFFF) == 0)
}
