#global private

#[Swag.NoInline]
func twoLess64(a, b, c: u64)->u64 => cast(u64) (a < b) + cast(u64) (b < c)

#[Swag.NoInline]
func twoLess32(a, b, c: u32)->u32 => cast(u32) (a < b) + cast(u32) (b < c)

#test
{
    let values64 = [0'u64, 1, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values64
    {
        for b in values64
        {
            for c in values64
                do Swag.assert(twoLess64(a, b, c) == cast(u64) (a < b) + cast(u64) (b < c))
        }
    }

    let values32 = [0'u32, 1, 0x80000000, 0xFFFFFFFF]
    for a in values32
    {
        for b in values32
        {
            for c in values32
                do Swag.assert(twoLess32(a, b, c) == cast(u32) (a < b) + cast(u32) (b < c))
        }
    }
}
