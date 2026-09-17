#global private

// Switch cases listing consecutive values are lowered as ranges; they join
// the packed table like single values. Every key, holes and far values
// included, must keep its answer.

#[Swag.Optimize(true), Swag.NoInline]
func dayLength(m: u32)->u8
{
    switch m
    {
    case 1, 3, 5, 7, 8, 10, 12:
        return 31
    case 2:
        return 28
    default:
        return 30
    }
}

#[Swag.Optimize(true), Swag.NoInline]
func bucket(v: u8)->s32
{
    switch v
    {
    case 0, 1, 2, 3:
        return -1
    case 4, 5:
        return 7
    case 9:
        return 2
    default:
        return 0
    }
}

func slowDayLength(m: u32)->u8
{
    if m == 2 do
        return 28
    if m == 1 or m == 3 or m == 5 or m == 7 or m == 8 or m == 10 or m == 12 do
        return 31
    return 30
}

func slowBucket(v: u8)->s32
{
    if v <= 3 do
        return -1
    if v == 4 or v == 5 do
        return 7
    if v == 9 do
        return 2
    return 0
}

#test
{
    for m in 0 until 40 do
        Swag.assert(dayLength(cast(u32) m) == slowDayLength(cast(u32) m))
    for m in [0xFFFFFFFF'u32, 0x80000001, 0x100, 0x107] do
        Swag.assert(dayLength(m) == 30)
    for v in 0 until 256 do
        Swag.assert(bucket(cast(u8) v) == slowBucket(cast(u8) v))
}
