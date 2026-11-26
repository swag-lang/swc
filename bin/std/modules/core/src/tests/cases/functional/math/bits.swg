#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func expectedLeadingZeros8(value: u8)->u8
{
    let input = cast(u16, value)
    var mask  = 0x80_u16
    for i in 8
    {
        if input & mask
        {
            return cast(u8, i)
        }

        mask >>= 1
    }

    return 8
}

func expectedTrailingZeros8(value: u8)->u8
{
    let input = cast(u16, value)
    var mask  = 1_u16
    for i in 8
    {
        if input & mask
        {
            return cast(u8, i)
        }

        mask <<= 1
    }

    return 8
}

func expectedCountOnes8(value: u8)->u8
{
    let input = cast(u16, value)
    var count = 0_u8
    var mask  = 1_u16
    for 8
    {
        if input & mask
        {
            count += 1
        }

        mask <<= 1
    }

    return count
}

func expectedReverse8(value: u8)->u8
{
    var result = 0_u16
    var source = cast(u16, value)
    for 8
    {
        result <<= 1
        result |= source & 1
        source >>= 1
    }

    return cast(u8, result)
}

func expectedRol8(value, shift: u8)->u8
{
    let amount = shift & 7
    if amount == 0
    {
        return value
    }

    let result = ((cast(u16, value) << amount) | (cast(u16, value) >> (8 - amount))) & 0xFF
    return cast(u8, result)
}

func expectedRor8(value, shift: u8)->u8
{
    let amount = shift & 7
    if amount == 0
    {
        return value
    }

    let result = ((cast(u16, value) >> amount) | (cast(u16, value) << (8 - amount))) & 0xFF
    return cast(u8, result)
}

func expectedLeadingZeros16(value: u16)->u16
{
    let input = cast(u32, value)
    var mask  = 0x8000_u32
    for i in 16
    {
        if input & mask
        {
            return cast(u16, i)
        }

        mask >>= 1
    }

    return 16
}

func expectedTrailingZeros16(value: u16)->u16
{
    let input = cast(u32, value)
    var mask  = 1_u32
    for i in 16
    {
        if input & mask
        {
            return cast(u16, i)
        }

        mask <<= 1
    }

    return 16
}

func expectedCountOnes16(value: u16)->u16
{
    let input = cast(u32, value)
    var count = 0_u16
    var mask  = 1_u32
    for 16
    {
        if input & mask
        {
            count += 1
        }

        mask <<= 1
    }

    return count
}

func expectedReverse16(value: u16)->u16
{
    var result = 0_u32
    var source = cast(u32, value)
    for 16
    {
        result <<= 1
        result |= source & 1
        source >>= 1
    }

    return cast(u16, result)
}

func expectedRol16(value: u16, shift: u8)->u16
{
    let amount = shift & 15
    if amount == 0
    {
        return value
    }

    let result = ((cast(u32, value) << amount) | (cast(u32, value) >> (16 - amount))) & 0xFFFF
    return cast(u16, result)
}

func expectedRor16(value: u16, shift: u8)->u16
{
    let amount = shift & 15
    if amount == 0
    {
        return value
    }

    let result = ((cast(u32, value) >> amount) | (cast(u32, value) << (16 - amount))) & 0xFFFF
    return cast(u16, result)
}

func expectedByteSwap16(value: u16)->u16
{
    let input = cast(u32, value)
    return cast(u16, ((input >> 8) | ((input << 8) & 0xFFFF)))
}

#test
{
    for value in 256
    {
        let input = cast(u8, value)
        Swag.require(Math.leadingZeros(input) == expectedLeadingZeros8(input))
        Swag.require(Math.trailingZeros(input) == expectedTrailingZeros8(input))
        Swag.require(Math.countOnes(input) == expectedCountOnes8(input))
        Swag.require(Math.reverse(input) == expectedReverse8(input))

        for shift in 16
        {
            let amount = cast(u8, shift)
            Swag.require(Math.rol(input, amount) == expectedRol8(input, amount))
            Swag.require(Math.ror(input, amount) == expectedRor8(input, amount))
        }
    }
}

#test
{
    for value in 65536
    {
        let input = cast(u16, value)
        Swag.require(Math.leadingZeros(input) == expectedLeadingZeros16(input))
        Swag.require(Math.trailingZeros(input) == expectedTrailingZeros16(input))
        Swag.require(Math.countOnes(input) == expectedCountOnes16(input))
        Swag.require(Math.reverse(input) == expectedReverse16(input))
        Swag.require(Math.byteSwap(input) == expectedByteSwap16(input))

        for shift in 32
        {
            let amount = cast(u8, shift)
            Swag.require(Math.rol(input, amount) == expectedRol16(input, amount))
            Swag.require(Math.ror(input, amount) == expectedRor16(input, amount))
        }
    }
}

#test
{
    Swag.require(Math.leadingZeros(0_u8) == 8_u8)
    Swag.require(Math.leadingZeros(0_u16) == 16_u16)
    Swag.require(Math.leadingZeros(0_u32) == 32_u32)
    Swag.require(Math.leadingZeros(0_u64) == 64_u64)

    Swag.require(Math.leadingZeros(0x80_u8) == 0_u8)
    Swag.require(Math.leadingZeros(0x8000_u16) == 0_u16)
    Swag.require(Math.leadingZeros(0x80000000_u32) == 0_u32)
    Swag.require(Math.leadingZeros(0x80000000_00000000_u64) == 0_u64)

    Swag.require(Math.leadingZeros(0x10_u8) == 3_u8)
    Swag.require(Math.leadingZeros(0x10_u16) == 11_u16)
    Swag.require(Math.leadingZeros(0x10_u32) == 27_u32)
    Swag.require(Math.leadingZeros(0x10_u64) == 59_u64)

    Swag.require(Math.trailingZeros(0_u8) == 8_u8)
    Swag.require(Math.trailingZeros(0_u16) == 16_u16)
    Swag.require(Math.trailingZeros(0_u32) == 32_u32)
    Swag.require(Math.trailingZeros(0_u64) == 64_u64)

    Swag.require(Math.trailingZeros(1_u8) == 0_u8)
    Swag.require(Math.trailingZeros(1_u16) == 0_u16)
    Swag.require(Math.trailingZeros(1_u32) == 0_u32)
    Swag.require(Math.trailingZeros(1_u64) == 0_u64)

    Swag.require(Math.trailingZeros(0x10_u8) == 4_u8)
    Swag.require(Math.trailingZeros(0x10_u16) == 4_u16)
    Swag.require(Math.trailingZeros(0x10_u32) == 4_u32)
    Swag.require(Math.trailingZeros(0x10_u64) == 4_u64)

    Swag.require(Math.trailingZeros(0x80_u8) == 7_u8)
    Swag.require(Math.trailingZeros(0x8000_u16) == 15_u16)
    Swag.require(Math.trailingZeros(0x80000000_u32) == 31_u32)
    Swag.require(Math.trailingZeros(0x80000000_00000000_u64) == 63_u64)

    Swag.require(Math.countOnes(0_u8) == 0_u8)
    Swag.require(Math.countOnes(0_u16) == 0_u16)
    Swag.require(Math.countOnes(0_u32) == 0_u32)
    Swag.require(Math.countOnes(0_u64) == 0_u64)

    Swag.require(Math.countOnes(0xFF_u8) == 8_u8)
    Swag.require(Math.countOnes(0xFFFF_u16) == 16_u16)
    Swag.require(Math.countOnes(0xFFFFFFFF_u32) == 32_u32)
    Swag.require(Math.countOnes(0xFFFFFFFF_FFFFFFFF_u64) == 64_u64)

    Swag.require(Math.countOnes(0xA5_u8) == 4_u8)
    Swag.require(Math.countOnes(0xA5A5_u16) == 8_u16)
    Swag.require(Math.countOnes(0xA5A5A5A5_u32) == 16_u32)
    Swag.require(Math.countOnes(0xA5A5A5A5_A5A5A5A5_u64) == 32_u64)
}

#test
{
    Swag.require(Math.rol(0x81_u8, 0_u8) == 0x81_u8)
    Swag.require(Math.ror(0x81_u8, 0_u8) == 0x81_u8)
    Swag.require(Math.rol(0x81_u8, 1_u8) == 0x03_u8)
    Swag.require(Math.ror(0x81_u8, 1_u8) == 0xC0_u8)
    Swag.require(Math.rol(0x12_u8, 4_u8) == 0x21_u8)
    Swag.require(Math.ror(0x12_u8, 4_u8) == 0x21_u8)
    Swag.require(Math.rol(0x81_u8, 8_u8) == 0x81_u8)
    Swag.require(Math.ror(0x81_u8, 8_u8) == 0x81_u8)

    Swag.require(Math.rol(0x8001_u16, 0_u8) == 0x8001_u16)
    Swag.require(Math.ror(0x8001_u16, 0_u8) == 0x8001_u16)
    Swag.require(Math.rol(0x8001_u16, 1_u8) == 0x0003_u16)
    Swag.require(Math.ror(0x8001_u16, 1_u8) == 0xC000_u16)
    Swag.require(Math.rol(0x1234_u16, 8_u8) == 0x3412_u16)
    Swag.require(Math.ror(0x1234_u16, 8_u8) == 0x3412_u16)
    Swag.require(Math.rol(0x8001_u16, 16_u8) == 0x8001_u16)
    Swag.require(Math.ror(0x8001_u16, 16_u8) == 0x8001_u16)

    Swag.require(Math.rol(0x80000001_u32, 0_u8) == 0x80000001_u32)
    Swag.require(Math.ror(0x80000001_u32, 0_u8) == 0x80000001_u32)
    Swag.require(Math.rol(0x80000001_u32, 1_u8) == 0x00000003_u32)
    Swag.require(Math.ror(0x80000001_u32, 1_u8) == 0xC0000000_u32)
    Swag.require(Math.rol(0x12345678_u32, 8_u8) == 0x34567812_u32)
    Swag.require(Math.ror(0x12345678_u32, 8_u8) == 0x78123456_u32)
    Swag.require(Math.rol(0x80000001_u32, 32_u8) == 0x80000001_u32)
    Swag.require(Math.ror(0x80000001_u32, 32_u8) == 0x80000001_u32)

    Swag.require(Math.rol(0x80000000_00000001_u64, 0_u8) == 0x80000000_00000001_u64)
    Swag.require(Math.ror(0x80000000_00000001_u64, 0_u8) == 0x80000000_00000001_u64)
    Swag.require(Math.rol(0x80000000_00000001_u64, 1_u8) == 0x00000000_00000003_u64)
    Swag.require(Math.ror(0x80000000_00000001_u64, 1_u8) == 0xC0000000_00000000_u64)
    Swag.require(Math.rol(0x01234567_89ABCDEF_u64, 8_u8) == 0x23456789_ABCDEF01_u64)
    Swag.require(Math.ror(0x01234567_89ABCDEF_u64, 8_u8) == 0xEF012345_6789ABCD_u64)
    Swag.require(Math.rol(0x80000000_00000001_u64, 64_u8) == 0x80000000_00000001_u64)
    Swag.require(Math.ror(0x80000000_00000001_u64, 64_u8) == 0x80000000_00000001_u64)

    Swag.require(Math.rol(0x8001_u16, 17_u8) == 0x0003_u16)
    Swag.require(Math.ror(0x8001_u16, 17_u8) == 0xC000_u16)
    Swag.require(Math.rol(0x80000001_u32, 33_u8) == 0x00000003_u32)
    Swag.require(Math.ror(0x80000001_u32, 33_u8) == 0xC0000000_u32)
    Swag.require(Math.rol(0x80000000_00000001_u64, 65_u8) == 0x00000000_00000003_u64)
    Swag.require(Math.ror(0x80000000_00000001_u64, 65_u8) == 0xC0000000_00000000_u64)
}

#test
{
    Swag.require(Math.reverse(0_u8) == 0_u8)
    Swag.require(Math.reverse(0_u16) == 0_u16)
    Swag.require(Math.reverse(0_u32) == 0_u32)
    Swag.require(Math.reverse(0_u64) == 0_u64)

    Swag.require(Math.reverse(0xFF_u8) == 0xFF_u8)
    Swag.require(Math.reverse(0xFFFF_u16) == 0xFFFF_u16)
    Swag.require(Math.reverse(0xFFFFFFFF_u32) == 0xFFFFFFFF_u32)
    Swag.require(Math.reverse(0xFFFFFFFF_FFFFFFFF_u64) == 0xFFFFFFFF_FFFFFFFF_u64)

    Swag.require(Math.reverse(0x01_u8) == 0x80_u8)
    Swag.require(Math.reverse(0x0001_u16) == 0x8000_u16)
    Swag.require(Math.reverse(0x00000001_u32) == 0x80000000_u32)
    Swag.require(Math.reverse(0x00000000_00000001_u64) == 0x80000000_00000000_u64)

    Swag.require(Math.reverse(0x80_u8) == 0x01_u8)
    Swag.require(Math.reverse(0x8000_u16) == 0x0001_u16)
    Swag.require(Math.reverse(0x80000000_u32) == 0x00000001_u32)
    Swag.require(Math.reverse(0x80000000_00000000_u64) == 0x00000000_00000001_u64)

    Swag.require(Math.reverse(0x12_u8) == 0x48_u8)
    Swag.require(Math.reverse(0x1234_u16) == 0x2C48_u16)
    Swag.require(Math.reverse(0x12345678_u32) == 0x1E6A2C48_u32)
    Swag.require(Math.reverse(0x01234567_89ABCDEF_u64) == 0xF7B3D591_E6A2C480_u64)

    Swag.require(Math.byteSwap(0_u16) == 0_u16)
    Swag.require(Math.byteSwap(0_u32) == 0_u32)
    Swag.require(Math.byteSwap(0_u64) == 0_u64)
    Swag.require(Math.byteSwap(0xFFFF_u16) == 0xFFFF_u16)
    Swag.require(Math.byteSwap(0xFFFFFFFF_u32) == 0xFFFFFFFF_u32)
    Swag.require(Math.byteSwap(0xFFFFFFFF_FFFFFFFF_u64) == 0xFFFFFFFF_FFFFFFFF_u64)
    Swag.require(Math.byteSwap(0x1234_u16) == 0x3412_u16)
    Swag.require(Math.byteSwap(0x12345678_u32) == 0x78563412_u32)
    Swag.require(Math.byteSwap(0x01234567_89ABCDEF_u64) == 0xEFCDAB89_67452301_u64)
}

// A single byte has no byte order, and a signed value keeps its exact bit pattern.
#test
{
    Swag.require(Math.byteSwap(0x12_u8) == 0x12_u8)
    Swag.require(Math.byteSwap(0x12_s8) == 0x12_s8)
    Swag.require(Math.byteSwap(-1_s8) == -1_s8)

    Swag.require(Math.byteSwap(800_s16) == 0x2003_s16)
    Swag.require(Math.byteSwap(0x2003_s16) == 800_s16)
    Swag.require(Math.byteSwap(-1_s16) == -1_s16)
    Swag.require(Math.byteSwap(0x00FF_s16) == cast #bit (s16, 0xFF00_u16))

    Swag.require(Math.byteSwap(0x12345678_s32) == 0x78563412_s32)
    Swag.require(Math.byteSwap(-1_s32) == -1_s32)
    Swag.require(Math.byteSwap(cast #bit (s32, 0xFFFFFF00_u32)) == 0x00FFFFFF_s32)

    Swag.require(Math.byteSwap(0x01234567_89ABCDEF_s64) == cast #bit (s64, 0xEFCDAB89_67452301_u64))
    Swag.require(Math.byteSwap(-1_s64) == -1_s64)

    // Swapping twice is the identity on every width, including the negative values a
    // signed field carries.
    Swag.require(Math.byteSwap(Math.byteSwap(-12345_s16)) == -12345_s16)
    Swag.require(Math.byteSwap(Math.byteSwap(-1234567_s32)) == -1234567_s32)
    Swag.require(Math.byteSwap(Math.byteSwap(-5_000_000_000_s64)) == -5_000_000_000_s64)
}
