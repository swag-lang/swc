#global private

#[Swag.NoInline]
func indexed(values: const [*]u64, index: u64)->u64
{
    let value = values[index]
    return cast(u64)(value != 0 and (value & (value - 1)) == 0)
}

#[Swag.NoInline]
func direct(value: u32)->bool => value != 0 and (value & (value - 1)) == 0

#test
{
    let values   = [0'u64, 1, 2, 3, 4, 6, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    let expected = [0'u64, 1, 1, 0, 1, 0, 1, 0]
    for value, index in values do
        Swag.assert(indexed(&values[0], index) == expected[index])

    let directValues   = [0'u32, 1, 2, 3, 4, 6, 0x80000000, 0xFFFFFFFF]
    let directExpected = [false, true, true, false, true, false, true, false]
    for value, index in directValues do
        Swag.assert(direct(value) == directExpected[index])
}
