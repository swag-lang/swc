#global private

#[Swag.NoInline]
func minUnsigned64(values: const [*]u64, index: u64)->u64
{
    let left  = values[index]
    let right = values[index + 1]
    return left < right ? left : right
}

#[Swag.NoInline]
func maxSigned64(values: const [*]s64, index: u64)->s64
{
    let left  = values[index]
    let right = values[index + 1]
    return left > right ? left : right
}

#test
{
    let unsigned = [0'u64, 1, 0xFFFFFFFFFFFFFFFF, 0x8000000000000000, 7]
    Swag.assert(minUnsigned64(&unsigned[0], 0) == 0)
    Swag.assert(minUnsigned64(&unsigned[0], 1) == 1)
    Swag.assert(minUnsigned64(&unsigned[0], 2) == 0x8000000000000000)
    Swag.assert(minUnsigned64(&unsigned[0], 3) == 7)

    let signed = [-9223372036854775807 - 1, -1, 0, 9223372036854775807, 7]
    Swag.assert(maxSigned64(&signed[0], 0) == -1)
    Swag.assert(maxSigned64(&signed[0], 1) == 0)
    Swag.assert(maxSigned64(&signed[0], 2) == 9223372036854775807)
    Swag.assert(maxSigned64(&signed[0], 3) == 9223372036854775807)
}
