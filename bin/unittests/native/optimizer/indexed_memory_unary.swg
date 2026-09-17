#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func increment64(values: [*] u64, index: u64)
{
    values[index] = values[index] + 1
}

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func decrement32(values: [*] u32, index: u64)
{
    values[index] = values[index] - 1
}

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func increment8(values: [*] u8, index: u64)
{
    values[index] = values[index] + 1
}

#test
{
    var values64: [4] u64 = [0, 1, 0x7FFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF]
    increment64(&values64[0], 0)
    increment64(&values64[0], 3)
    Swag.assert(values64[0] == 1 and values64[1] == 1 and values64[2] == 0x7FFFFFFFFFFFFFFF and values64[3] == 0)

    var values32: [4] u32 = [0, 1, 0x80000000, 0xFFFFFFFF]
    decrement32(&values32[0], 0)
    decrement32(&values32[0], 3)
    Swag.assert(values32[0] == 0xFFFFFFFF and values32[1] == 1 and values32[2] == 0x80000000 and values32[3] == 0xFFFFFFFE)

    var values8: [4] u8 = [0, 1, 127, 255]
    increment8(&values8[0], 2)
    increment8(&values8[0], 3)
    Swag.assert(values8[0] == 0 and values8[1] == 1 and values8[2] == 128 and values8[3] == 0)
}
