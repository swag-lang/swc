#global private

#[Swag.NoInline]
func different32(a: s32, b: s32)->u32
{
    var result = 1'u32
    if a == b do
        result = 0
    return result
}

#[Swag.NoInline]
func different64(a: s64, b: s64)->u64
{
    var result = 1'u64
    if a == b do
        result = 0
    return result
}

#[Swag.NoInline]
func less64(a: s64, b: s64)->u64
{
    var result = 0'u64
    if a < b do
        result = 1
    return result
}

#test
{
    for index in 17
    {
        Swag.assert(different32(index, index) == 0)
        Swag.assert(different32(index, index + 1) == 1)
        Swag.assert(different64(index, index) == 0)
        Swag.assert(different64(index, index + 1) == 1)
    }
    Swag.assert(different32(-1, 0) == 1)
    Swag.assert(different64(-1, 0) == 1)
    Swag.assert(less64(-1, 0) == 1)
    Swag.assert(less64(0, -1) == 0)
    Swag.assert(less64(0, 0) == 0)
}
