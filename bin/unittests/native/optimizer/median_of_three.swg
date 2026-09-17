#global private

#[Swag.NoInline]
func median3(values: const [*]u64, index: u64)->u64
{
    let first  = values[index]
    let second = values[index + 1]
    let third  = values[index + 2]
    return Swag.max(Swag.min(first, second), Swag.min(Swag.max(first, second), third))
}

#[Swag.NoInline]
func median3Signed(values: const [*]s64, index: u64)->s64
{
    let first  = values[index]
    let second = values[index + 1]
    let third  = values[index + 2]
    return Swag.max(Swag.min(first, second), Swag.min(Swag.max(first, second), third))
}

#[Swag.NoInline]
func median3Narrow(values: const [*]u32, index: u64)->u32
{
    let first  = values[index]
    let second = values[index + 1]
    let third  = values[index + 2]
    return Swag.max(Swag.min(first, second), Swag.min(Swag.max(first, second), third))
}

#[Swag.NoInline]
func median3SignedNarrow(values: const [*]s32, index: u64)->s32
{
    let first  = values[index]
    let second = values[index + 1]
    let third  = values[index + 2]
    return Swag.max(Swag.min(first, second), Swag.min(Swag.max(first, second), third))
}

#test
{
    let values = [1'u64, 2, 3, 1, 3, 2, 2, 1, 3, 2, 3, 1, 3, 1, 2, 3, 2, 1,
                  0, 0xFFFFFFFFFFFFFFFF, 7]
    for index in 6 do
        Swag.assert(median3(&values[0], cast(u64) index * 3) == 2)
    Swag.assert(median3(&values[0], 18) == 7)

    let signedValues = [-9's64, 4, 1, -1, -1, 7, 0x7FFFFFFFFFFFFFFF, -0x8000000000000000, 0]
    Swag.assert(median3Signed(&signedValues[0], 0) == 1)
    Swag.assert(median3Signed(&signedValues[0], 3) == -1)
    Swag.assert(median3Signed(&signedValues[0], 6) == 0)

    let narrowValues = [1'u32, 2, 3, 1, 3, 2, 2, 1, 3, 2, 3, 1, 3, 1, 2, 3, 2, 1,
                        0, 0xFFFFFFFF, 7]
    for index in 6 do
        Swag.assert(median3Narrow(&narrowValues[0], cast(u64) index * 3) == 2)
    Swag.assert(median3Narrow(&narrowValues[0], 18) == 7)

    let signedNarrowValues = [-9's32, 4, 1, -1, -1, 7, 0x7FFFFFFF, -0x7FFFFFFF - 1, 0]
    Swag.assert(median3SignedNarrow(&signedNarrowValues[0], 0) == 1)
    Swag.assert(median3SignedNarrow(&signedNarrowValues[0], 3) == -1)
    Swag.assert(median3SignedNarrow(&signedNarrowValues[0], 6) == 0)
}
