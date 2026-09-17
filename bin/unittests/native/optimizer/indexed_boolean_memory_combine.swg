#global private

#[Swag.NoInline]
func lessAndNonzero(values: const [*]u64, index: u64) -> u64 => cast(u64)(values[index] < values[index + 1] and values[index] != 0)

#[Swag.NoInline]
func equalOrZero(values: const [*]u64, index: u64) -> u64 => cast(u64)(values[index] == values[index + 1] or values[index] == 0)

#test
{
    let values = [0'u64, 0, 1, 2, 2, 0xFFFFFFFFFFFFFFFF, 7]
    Swag.assert(lessAndNonzero(&values[0], 0) == 0)
    Swag.assert(lessAndNonzero(&values[0], 1) == 0)
    Swag.assert(lessAndNonzero(&values[0], 2) == 1)
    Swag.assert(lessAndNonzero(&values[0], 3) == 0)
    Swag.assert(lessAndNonzero(&values[0], 4) == 1)
    Swag.assert(lessAndNonzero(&values[0], 5) == 0)

    Swag.assert(equalOrZero(&values[0], 0) == 1)
    Swag.assert(equalOrZero(&values[0], 1) == 1)
    Swag.assert(equalOrZero(&values[0], 2) == 0)
    Swag.assert(equalOrZero(&values[0], 3) == 1)
    Swag.assert(equalOrZero(&values[0], 4) == 0)
    Swag.assert(equalOrZero(&values[0], 5) == 0)
}
