#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func addOne(values: const [*]u64, index: u64)->u64 => values[index] + 1

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func subtractOne(values: const [*]u64, index: u64)->u64 => values[index] - 1

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func isolateLowestZero(values: const [*]u64, index: u64)->u64
{
    let value = values[index]
    return ~value & (value + 1)
}

#test
{
    let values = [0'u64, 1, 2, 0x7FFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFE, 0xFFFFFFFFFFFFFFFF]
    for value, index in values
    {
        Swag.assert(addOne(&values[0], index) == value + #wrap 1)
        Swag.assert(subtractOne(&values[0], index) == value - #wrap 1)
        Swag.assert(isolateLowestZero(&values[0], index) == (~value & (value + #wrap 1)))
    }
}
