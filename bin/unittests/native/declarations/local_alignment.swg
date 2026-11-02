#global private

#[Swag.Align(32)]
struct LocalAligned32
{
    values: [4]u64
}

#[Swag.Align(64)]
struct LocalAligned64
{
    values: [8]u64
}

struct LocalAlignedField
{
    head: u8
    #[Swag.Align(128)]
    hot: u64
}

#[Swag.NoInline]
func localAlignmentRemainder()->u64
{
    var value: LocalAligned64
    value.values[3] = 37
    Swag.assert(value.values[3] == 37)
    return cast(u64, &value) % 64
}

#[Swag.NoInline]
func nestedAlignmentRemainder(depth: u32)->u64
{
    var value: LocalAligned64
    value.values[2] = depth
    var remainder = localAlignmentRemainder() | (cast(u64, &value) % 64)
    if depth != 0 do
        remainder |= nestedAlignmentRemainder(depth - 1)
    Swag.assert(value.values[2] == depth)
    return remainder
}

#test
{
    let remainder = nestedAlignmentRemainder(16)
    Swag.assert(remainder == 0)
}

#test
{
    var values: [3]LocalAlignedField
    for &value, index in values
    {
        value.head = cast(u8, index + 1)
        value.hot  = index + 17
        Swag.assert(cast(u64, value) % 128 == 0)
        Swag.assert(cast(u64, &value.hot) % 128 == 0)
    }
    for value, index in values do
        Swag.assert(value.head == index + 1 and value.hot == index + 17)
}

#[Swag.NoInline]
func makeAlignedLocal(seed: u64)->LocalAligned32
{
    var result: LocalAligned32
    Swag.assert(cast(u64, &result) % 32 == 0)
    for &value, index in result.values do
        value[] = seed + index
    return result
}

#test
{
    let value = makeAlignedLocal(41)
    Swag.assert(cast(u64, &value) % 32 == 0)
    for entry, index in value.values do
        Swag.assert(entry == 41 + index)
}
