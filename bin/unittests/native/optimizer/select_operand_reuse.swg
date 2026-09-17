#global private

#[Swag.NoInline]
func max3(values: const [*]u64, index: u64)->u64 => Swag.max(values[index], Swag.max(values[index + 1], values[index + 2]))

#[Swag.NoInline]
func min3(values: const [*]s32, index: u64)->s32 => Swag.min(values[index], Swag.min(values[index + 1], values[index + 2]))

#test
{
    let unsigned = [0'u64, 1, 2, 3, 2, 1, 4, 4, 4, 0xFFFFFFFFFFFFFFFF, 0, 1]
    let unsignedExpected = [2'u64, 3, 4, 0xFFFFFFFFFFFFFFFF]
    for value, index in unsignedExpected do Swag.assert(max3(&unsigned[0], index * 3) == value)

    let signed = [-3's32, -2, -1, 3, 2, 1, -4, -4, -4, -2147483648, 0, 2147483647]
    let signedExpected = [-3's32, 1, -4, -2147483648]
    for value, index in signedExpected do Swag.assert(min3(&signed[0], index * 3) == value)
}
