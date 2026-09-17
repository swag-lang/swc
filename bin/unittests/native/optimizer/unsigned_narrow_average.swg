#global private

#[Swag.NoInline]
func floorAverage(values: const [*]u16, index: u64)->u16
{
    let left  = values[index]
    let right = values[index + 1]
    return (left & right) + ((left ^ right) >> 1)
}

#[Swag.NoInline]
func ceilAverage(values: const [*]u16, index: u64)->u16
{
    let left  = values[index]
    let right = values[index + 1]
    return (left | right) - ((left ^ right) >> 1)
}

#[Swag.NoInline]
func floorAverage8(values: const [*]u8, index: u64)->u8
{
    let left  = values[index]
    let right = values[index + 1]
    return (left & right) + ((left ^ right) >> 1)
}

#[Swag.NoInline]
func ceilAverage8(values: const [*]u8, index: u64)->u8
{
    let left  = values[index]
    let right = values[index + 1]
    return (left | right) - ((left ^ right) >> 1)
}

#test
{
    let values = [0'u16, 0, 0, 1, 1, 2, 2, 3, 0, 0xFFFF, 0xFFFE, 0xFFFF]
    let floors = [0'u16, 0, 1, 2, 0x7FFF, 0xFFFE]
    let ceils  = [0'u16, 1, 2, 3, 0x8000, 0xFFFF]
    for floor, index in floors
    {
        Swag.assert(floorAverage(&values[0], index * 2) == floor)
        Swag.assert(ceilAverage(&values[0], index * 2) == ceils[index])
    }

    let values8 = [0'u8, 1, 1, 2, 0, 0xFF, 0xFE, 0xFF]
    let floors8 = [0'u8, 1, 0x7F, 0xFE]
    let ceils8  = [1'u8, 2, 0x80, 0xFF]
    for floor, index in floors8
    {
        Swag.assert(floorAverage8(&values8[0], index * 2) == floor)
        Swag.assert(ceilAverage8(&values8[0], index * 2) == ceils8[index])
    }
}
