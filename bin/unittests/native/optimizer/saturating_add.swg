#global private

#[Swag.NoInline]
func saturated64(left, right: u64)->u64 => left > 0xFFFFFFFFFFFFFFFF - right ? 0xFFFFFFFFFFFFFFFF : left + right

#[Swag.NoInline]
func saturated32(left, right: u32)->u32 => left > 0xFFFFFFFF - right ? 0xFFFFFFFF : left + right

#[Swag.NoInline]
func indexed64(values: const [*]u64, index: u64)->u64 => saturated64(values[index], values[index + 1])

#[Swag.NoInline]
func indexed32(values: const [*]u32, index: u64)->u32
{
    let left  = values[index]
    let right = values[index + 1]
    let sum   = left + #wrap right
    return sum < left ? 0xFFFFFFFF : sum
}

#test
{
    let values = [0'u64, 0, 1, 2, 0xFFFFFFFFFFFFFFFE, 1, 0xFFFFFFFFFFFFFFFF, 1, 0x8000000000000000, 0x8000000000000000]
    let expected = [0'u64, 3, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF]
    for value, index in expected
    {
        let source = index * 2
        Swag.assert(saturated64(values[source], values[source + 1]) == value)
        Swag.assert(indexed64(&values[0], source) == value)
    }

    let values32 = [0'u32, 0, 1, 2, 0xFFFFFFFE, 1, 0xFFFFFFFF, 1, 0x80000000, 0x80000000]
    let expected32 = [0'u32, 3, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF]
    for value, index in expected32
    {
        let source = index * 2
        Swag.assert(saturated32(values32[source], values32[source + 1]) == value)
        Swag.assert(indexed32(&values32[0], source) == value)
    }
}
