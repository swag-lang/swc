#global private

#[Swag.NoInline]
func shiftLeft64(values: [*] u64, index: u64)
{
    values[index] = values[index] << 1
}

#[Swag.NoInline]
func shiftRight64(values: [*] u64, index: u64)
{
    values[index] = values[index] >> 7
}

#[Swag.NoInline]
func shiftArithmetic64(values: [*] s64, index: u64)
{
    values[index] = values[index] >> 3
}

#[Swag.NoInline]
func shiftLeft32(values: [*] u32, index: u64)
{
    values[index] = values[index] << 5
}

#[Swag.NoInline]
func shiftRight8(values: [*] u8, index: u64)
{
    values[index] = values[index] >> 1
}

#test
{
    var values64: [4] u64 = [1, 0x80, 0xFFFFFFFFFFFFFFFF, 0]
    shiftLeft64(&values64[0], 0)
    shiftRight64(&values64[0], 1)
    Swag.assert(values64[0] == 2 and values64[1] == 1 and values64[2] == 0xFFFFFFFFFFFFFFFF and values64[3] == 0)

    var signed64: [4] s64 = [-8, -1, 8, 0]
    shiftArithmetic64(&signed64[0], 0)
    shiftArithmetic64(&signed64[0], 2)
    Swag.assert(signed64[0] == -1 and signed64[1] == -1 and signed64[2] == 1 and signed64[3] == 0)

    var values32: [4] u32 = [1, 0x80000000, 0xFFFFFFFF, 0]
    shiftLeft32(&values32[0], 0)
    shiftLeft32(&values32[0], 1)
    Swag.assert(values32[0] == 32 and values32[1] == 0 and values32[2] == 0xFFFFFFFF and values32[3] == 0)

    var values8: [4] u8 = [0, 1, 0x80, 0xFF]
    shiftRight8(&values8[0], 2)
    shiftRight8(&values8[0], 3)
    Swag.assert(values8[0] == 0 and values8[1] == 1 and values8[2] == 0x40 and values8[3] == 0x7F)
}
