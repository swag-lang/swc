#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shiftLeft64(values: [*] u64, index, amount: u64)
{
    values[index] = values[index] << amount
}

#[Swag.NoInline]
func shiftRight32(values: [*] u32, index: u64, amount: u32)
{
    values[index] = values[index] >> amount
}

#[Swag.NoInline]
func shiftArithmetic64(values: [*] s64, index: u64, amount: u32)
{
    values[index] = values[index] >> amount
}

#test
{
    var left: [4] u64 = [1, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF, 7]
    shiftLeft64(&left[0], 0, 63)
    shiftLeft64(&left[0], 2, 4)
    Swag.assert(left[0] == 0x8000000000000000 and left[1] == 0x8000000000000000 and left[2] == 0xFFFFFFFFFFFFFFF0 and left[3] == 7)

    var right: [4] u32 = [1, 0x80000000, 0xFFFFFFFF, 7]
    shiftRight32(&right[0], 1, 31)
    shiftRight32(&right[0], 2, 4)
    Swag.assert(right[0] == 1 and right[1] == 1 and right[2] == 0x0FFFFFFF and right[3] == 7)

    var arithmetic: [4] s64 = [1, -1, -9223372036854775808's64, 7]
    shiftArithmetic64(&arithmetic[0], 1, 63)
    shiftArithmetic64(&arithmetic[0], 2, 4)
    Swag.assert(arithmetic[0] == 1 and arithmetic[1] == -1 and arithmetic[2] == -576460752303423488 and arithmetic[3] == 7)
}
