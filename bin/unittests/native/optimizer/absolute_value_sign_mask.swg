#global private

#[Swag.NoInline]
func indexedAbs64(values: const [*]s64, index: u64)->s64 => Swag.abs(values[index])

#[Swag.NoInline]
func indexedAbs32(values: const [*]s32, index: u64)->s32 => Swag.abs(values[index])

#test
{
    let values64   = [-9223372036854775808_s64, -5000000000, -1, 0, 1, 5000000000, 9223372036854775807]
    let expected64 = [-9223372036854775808_s64, 5000000000, 1, 0, 1, 5000000000, 9223372036854775807]
    for value, index in expected64
    {
        Swag.require(indexedAbs64(&values64[0], index) == value)
    }

    let values32   = [-2147483648_s32, -123456, -1, 0, 1, 123456, 2147483647]
    let expected32 = [-2147483648_s32, 123456, 1, 0, 1, 123456, 2147483647]
    for value, index in expected32
    {
        Swag.require(indexedAbs32(&values32[0], index) == value)
    }
}
