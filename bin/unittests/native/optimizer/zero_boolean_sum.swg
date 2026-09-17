#global private

#[Swag.NoInline]
func zeroCount64(a, b: u64)->u64 => cast(u64)(a == 0) + cast(u64)(b == 0)

#[Swag.NoInline]
func zeroCount32(a, b: u32)->u32 => cast(u32)(a == 0) + cast(u32)(b == 0)

#test
{
    let values64 = [0'u64, 1, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values64
    {
        for b in values64
            do Swag.assert(zeroCount64(a, b) == cast(u64)(a == 0) + cast(u64)(b == 0))
    }

    let values32 = [0'u32, 1, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF]
    for a in values32
    {
        for b in values32
            do Swag.assert(zeroCount32(a, b) == cast(u32)(a == 0) + cast(u32)(b == 0))
    }
}
