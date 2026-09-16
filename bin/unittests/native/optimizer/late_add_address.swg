#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func add64(a, b: u64)->u64 => a + b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func add32(a, b: u32)->u32 => a + b

#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checkedAdd(a, b: s64)->s64 => a + b

#[Swag.NoInline]
func observe(a: u64)->u64 => a ^ 0xABCDE

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func addThenCall(a, b: u64)->u64 => observe(a + b)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func sumPairs(values: const [..] u64)->u64
{
    var total = 0'u64
    for i in 0 until values.count - 1 do
        total += values[i] + values[i + 1]
    return total
}

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    var expected = 0'u64
    for i in 0 until values.count - 1 do
        expected += values[i] + values[i + 1]
    Swag.assert(sumPairs(values) == expected)
    for a in values
    {
        for b in values
        {
            Swag.assert(add64(a, b) == a + b)
            Swag.assert(addThenCall(a, b) == ((a + b) ^ 0xABCDE))
            let a32 = cast(u32) (a & 0xFFFFFFFF)
            let b32 = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(add32(a32, b32) == a32 + b32)
        }
    }
    Swag.assert(checkedAdd(-123, 45) == -78)
    Swag.assert(checkedAdd(0x7FFFFFFFFFFFFFFE, 1) == 0x7FFFFFFFFFFFFFFF)
}
