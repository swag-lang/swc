#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline]
func scaled64(x, y: u64)->u64 => x * 33 + y
#[Swag.NoInline]
func retainedAddend64(x, y: u64)->u64 => (x * 33 + y) ^ y
#[Swag.NoInline]
func reversed64(x, y: u64)->u64 => y + x * 257
#[Swag.NoInline]
func scaled32(x, y: u32)->u32 => x * 17 + y
#[Swag.NoInline]
func signed64(x, y: s64)->s64 => x * 33 + y
#[Swag.NoInline]
func chain64(a, b, c, d: u64)->u64 => ((a * 33 + b) * 33 + c) * 33 + d

#[Swag.NoInline]
func dynamic64(x, y, coefficient: u64)->u64 => x * coefficient + y
#[Swag.NoInline]
func dynamic32(x, y, coefficient: u32)->u32 => x * coefficient + y
#[Swag.NoInline]
func dynamicSigned64(x, y, coefficient: s64)->s64 => x * coefficient + y
#[Swag.NoInline]
func dynamicChain64(a, b, c, d, coefficient: u64)->u64 => ((a * coefficient + b) * coefficient + c) * coefficient + d

#test
{
    let values = [0'u64, 1, 255, 65535, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for x in values
    {
        for y in values
        {
            Swag.assert(scaled64(x, y) == dynamic64(x, y, 33))
            Swag.assert(retainedAddend64(x, y) == (dynamic64(x, y, 33) ^ y))
            Swag.assert(reversed64(x, y) == dynamic64(x, y, 257))
            Swag.assert(chain64(x, y, x, y) == dynamicChain64(x, y, x, y, 33))
        }
    }
}

#test
{
    let values = [0'u32, 1, 255, 65535, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF]
    for x in values
    {
        for y in values do
            Swag.assert(scaled32(x, y) == dynamic32(x, y, 17))
    }
}

#test
{
    let values = [-9223372036854775808's64, -65537, -1, 0, 1, 65537, 9223372036854775807]
    for x in values
    {
        for y in values do
            Swag.assert(signed64(x, y) == dynamicSigned64(x, y, 33))
    }
}
