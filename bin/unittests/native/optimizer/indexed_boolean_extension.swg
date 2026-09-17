#global private

#[Swag.NoInline]
func isZero64(values: [*] u64, index: u64)->u64 => cast(u64)(values[index] == 0)

#[Swag.NoInline]
func isNonzero32(values: [*] u32, index: u64)->u32 => cast(u32)(values[index] != 0)

#test
{
    var values64 = [0'u64, 1, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    var values32 = [0'u32, 1, 0x80000000, 0xFFFFFFFF]
    for i in values64.count
    {
        Swag.assert(isZero64(&values64[0], i) == cast(u64)(values64[i] == 0))
        Swag.assert(isNonzero32(&values32[0], i) == cast(u32)(values32[i] != 0))
    }
}
