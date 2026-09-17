#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func multiply64(values: [*] u64, index, value: u64)
{
    values[index] = values[index] * value
}

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func multiply32(values: [*] u32, index: u64, value: u32)
{
    values[index] = values[index] * value
}

#test
{
    var values64: [4] u64 = [0, 1, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    multiply64(&values64[0], 0, 19)
    multiply64(&values64[0], 1, 17)
    multiply64(&values64[0], 2, 3)
    multiply64(&values64[0], 3, 2)
    Swag.assert(values64[0] == 0 and values64[1] == 17 and values64[2] == 0x8000000000000000 and values64[3] == 0xFFFFFFFFFFFFFFFE)

    var values32: [4] u32 = [0, 1, 0x80000000, 0xFFFFFFFF]
    multiply32(&values32[0], 0, 19)
    multiply32(&values32[0], 1, 17)
    multiply32(&values32[0], 2, 3)
    multiply32(&values32[0], 3, 2)
    Swag.assert(values32[0] == 0 and values32[1] == 17 and values32[2] == 0x80000000 and values32[3] == 0xFFFFFFFE)
}
