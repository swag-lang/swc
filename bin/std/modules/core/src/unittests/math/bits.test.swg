#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func expectedLeadingZeros8(value: u8)->u8
{
    let input = cast(u16) value
    var mask  = 0x80'u16
    for i in 8
    {
        if input & mask do
            return cast(u8) i
        mask >>= 1
    }

    return 8
}

func expectedTrailingZeros8(value: u8)->u8
{
    let input = cast(u16) value
    var mask  = 1'u16
    for i in 8
    {
        if input & mask do
            return cast(u8) i
        mask <<= 1
    }

    return 8
}

func expectedCountOnes8(value: u8)->u8
{
    let input = cast(u16) value
    var count = 0'u8
    var mask  = 1'u16
    for 8
    {
        if input & mask do
            count += 1
        mask      <<= 1
    }

    return count
}

func expectedReverse8(value: u8)->u8
{
    var result = 0'u16
    var source = cast(u16) value
    for 8
    {
        result <<= 1
        result |= source & 1
        source >>= 1
    }

    return cast(u8) result
}

func expectedRol8(value, shift: u8)->u8
{
    let amount = shift & 7
    if amount == 0 do
        return value
    let result = ((cast(u16) value << amount) | (cast(u16) value >> (8 - amount))) & 0xFF
    return cast(u8) result
}

func expectedRor8(value, shift: u8)->u8
{
    let amount = shift & 7
    if amount == 0 do
        return value
    let result = ((cast(u16) value >> amount) | (cast(u16) value << (8 - amount))) & 0xFF
    return cast(u8) result
}

func expectedLeadingZeros16(value: u16)->u16
{
    let input = cast(u32) value
    var mask  = 0x8000'u32
    for i in 16
    {
        if input & mask do
            return cast(u16) i
        mask >>= 1
    }

    return 16
}

func expectedTrailingZeros16(value: u16)->u16
{
    let input = cast(u32) value
    var mask  = 1'u32
    for i in 16
    {
        if input & mask do
            return cast(u16) i
        mask <<= 1
    }

    return 16
}

func expectedCountOnes16(value: u16)->u16
{
    let input = cast(u32) value
    var count = 0'u16
    var mask  = 1'u32
    for 16
    {
        if input & mask do
            count += 1
        mask      <<= 1
    }

    return count
}

func expectedReverse16(value: u16)->u16
{
    var result = 0'u32
    var source = cast(u32) value
    for 16
    {
        result <<= 1
        result |= source & 1
        source >>= 1
    }

    return cast(u16) result
}

func expectedRol16(value: u16, shift: u8)->u16
{
    let amount = shift & 15
    if amount == 0 do
        return value
    let result = ((cast(u32) value << amount) | (cast(u32) value >> (16 - amount))) & 0xFFFF
    return cast(u16) result
}

func expectedRor16(value: u16, shift: u8)->u16
{
    let amount = shift & 15
    if amount == 0 do
        return value
    let result = ((cast(u32) value >> amount) | (cast(u32) value << (16 - amount))) & 0xFFFF
    return cast(u16) result
}

func expectedByteswap16(value: u16)->u16
{
    let input = cast(u32) value
    return cast(u16) ((input >> 8) | ((input << 8) & 0xFFFF))
}

#test
{
    for value in 256
    {
        let input = cast(u8) value
        @assert(Math.leadingZeros(input) == expectedLeadingZeros8(input))
        @assert(Math.trailingZeros(input) == expectedTrailingZeros8(input))
        @assert(Math.countOnes(input) == expectedCountOnes8(input))
        @assert(Math.reverse(input) == expectedReverse8(input))

        for shift in 16
        {
            let amount = cast(u8) shift
            @assert(Math.rol(input, amount) == expectedRol8(input, amount))
            @assert(Math.ror(input, amount) == expectedRor8(input, amount))
        }
    }
}

#test
{
    for value in 65536
    {
        let input = cast(u16) value
        @assert(Math.leadingZeros(input) == expectedLeadingZeros16(input))
        @assert(Math.trailingZeros(input) == expectedTrailingZeros16(input))
        @assert(Math.countOnes(input) == expectedCountOnes16(input))
        @assert(Math.reverse(input) == expectedReverse16(input))
        @assert(Math.byteswap(input) == expectedByteswap16(input))

        for shift in 32
        {
            let amount = cast(u8) shift
            @assert(Math.rol(input, amount) == expectedRol16(input, amount))
            @assert(Math.ror(input, amount) == expectedRor16(input, amount))
        }
    }
}

#test
{
    @assert(Math.leadingZeros(0'u8) == 8'u8)
    @assert(Math.leadingZeros(0'u16) == 16'u16)
    @assert(Math.leadingZeros(0'u32) == 32'u32)
    @assert(Math.leadingZeros(0'u64) == 64'u64)

    @assert(Math.leadingZeros(0x80'u8) == 0'u8)
    @assert(Math.leadingZeros(0x8000'u16) == 0'u16)
    @assert(Math.leadingZeros(0x80000000'u32) == 0'u32)
    @assert(Math.leadingZeros(0x80000000_00000000'u64) == 0'u64)

    @assert(Math.leadingZeros(0x10'u8) == 3'u8)
    @assert(Math.leadingZeros(0x10'u16) == 11'u16)
    @assert(Math.leadingZeros(0x10'u32) == 27'u32)
    @assert(Math.leadingZeros(0x10'u64) == 59'u64)

    @assert(Math.trailingZeros(0'u8) == 8'u8)
    @assert(Math.trailingZeros(0'u16) == 16'u16)
    @assert(Math.trailingZeros(0'u32) == 32'u32)
    @assert(Math.trailingZeros(0'u64) == 64'u64)

    @assert(Math.trailingZeros(1'u8) == 0'u8)
    @assert(Math.trailingZeros(1'u16) == 0'u16)
    @assert(Math.trailingZeros(1'u32) == 0'u32)
    @assert(Math.trailingZeros(1'u64) == 0'u64)

    @assert(Math.trailingZeros(0x10'u8) == 4'u8)
    @assert(Math.trailingZeros(0x10'u16) == 4'u16)
    @assert(Math.trailingZeros(0x10'u32) == 4'u32)
    @assert(Math.trailingZeros(0x10'u64) == 4'u64)

    @assert(Math.trailingZeros(0x80'u8) == 7'u8)
    @assert(Math.trailingZeros(0x8000'u16) == 15'u16)
    @assert(Math.trailingZeros(0x80000000'u32) == 31'u32)
    @assert(Math.trailingZeros(0x80000000_00000000'u64) == 63'u64)

    @assert(Math.countOnes(0'u8) == 0'u8)
    @assert(Math.countOnes(0'u16) == 0'u16)
    @assert(Math.countOnes(0'u32) == 0'u32)
    @assert(Math.countOnes(0'u64) == 0'u64)

    @assert(Math.countOnes(0xFF'u8) == 8'u8)
    @assert(Math.countOnes(0xFFFF'u16) == 16'u16)
    @assert(Math.countOnes(0xFFFFFFFF'u32) == 32'u32)
    @assert(Math.countOnes(0xFFFFFFFF_FFFFFFFF'u64) == 64'u64)

    @assert(Math.countOnes(0xA5'u8) == 4'u8)
    @assert(Math.countOnes(0xA5A5'u16) == 8'u16)
    @assert(Math.countOnes(0xA5A5A5A5'u32) == 16'u32)
    @assert(Math.countOnes(0xA5A5A5A5_A5A5A5A5'u64) == 32'u64)
}

#test
{
    @assert(Math.rol(0x81'u8, 0'u8) == 0x81'u8)
    @assert(Math.ror(0x81'u8, 0'u8) == 0x81'u8)
    @assert(Math.rol(0x81'u8, 1'u8) == 0x03'u8)
    @assert(Math.ror(0x81'u8, 1'u8) == 0xC0'u8)
    @assert(Math.rol(0x12'u8, 4'u8) == 0x21'u8)
    @assert(Math.ror(0x12'u8, 4'u8) == 0x21'u8)
    @assert(Math.rol(0x81'u8, 8'u8) == 0x81'u8)
    @assert(Math.ror(0x81'u8, 8'u8) == 0x81'u8)

    @assert(Math.rol(0x8001'u16, 0'u8) == 0x8001'u16)
    @assert(Math.ror(0x8001'u16, 0'u8) == 0x8001'u16)
    @assert(Math.rol(0x8001'u16, 1'u8) == 0x0003'u16)
    @assert(Math.ror(0x8001'u16, 1'u8) == 0xC000'u16)
    @assert(Math.rol(0x1234'u16, 8'u8) == 0x3412'u16)
    @assert(Math.ror(0x1234'u16, 8'u8) == 0x3412'u16)
    @assert(Math.rol(0x8001'u16, 16'u8) == 0x8001'u16)
    @assert(Math.ror(0x8001'u16, 16'u8) == 0x8001'u16)

    @assert(Math.rol(0x80000001'u32, 0'u8) == 0x80000001'u32)
    @assert(Math.ror(0x80000001'u32, 0'u8) == 0x80000001'u32)
    @assert(Math.rol(0x80000001'u32, 1'u8) == 0x00000003'u32)
    @assert(Math.ror(0x80000001'u32, 1'u8) == 0xC0000000'u32)
    @assert(Math.rol(0x12345678'u32, 8'u8) == 0x34567812'u32)
    @assert(Math.ror(0x12345678'u32, 8'u8) == 0x78123456'u32)
    @assert(Math.rol(0x80000001'u32, 32'u8) == 0x80000001'u32)
    @assert(Math.ror(0x80000001'u32, 32'u8) == 0x80000001'u32)

    @assert(Math.rol(0x80000000_00000001'u64, 0'u8) == 0x80000000_00000001'u64)
    @assert(Math.ror(0x80000000_00000001'u64, 0'u8) == 0x80000000_00000001'u64)
    @assert(Math.rol(0x80000000_00000001'u64, 1'u8) == 0x00000000_00000003'u64)
    @assert(Math.ror(0x80000000_00000001'u64, 1'u8) == 0xC0000000_00000000'u64)
    @assert(Math.rol(0x01234567_89ABCDEF'u64, 8'u8) == 0x23456789_ABCDEF01'u64)
    @assert(Math.ror(0x01234567_89ABCDEF'u64, 8'u8) == 0xEF012345_6789ABCD'u64)
    @assert(Math.rol(0x80000000_00000001'u64, 64'u8) == 0x80000000_00000001'u64)
    @assert(Math.ror(0x80000000_00000001'u64, 64'u8) == 0x80000000_00000001'u64)

    @assert(Math.rol(0x8001'u16, 17'u8) == 0x0003'u16)
    @assert(Math.ror(0x8001'u16, 17'u8) == 0xC000'u16)
    @assert(Math.rol(0x80000001'u32, 33'u8) == 0x00000003'u32)
    @assert(Math.ror(0x80000001'u32, 33'u8) == 0xC0000000'u32)
    @assert(Math.rol(0x80000000_00000001'u64, 65'u8) == 0x00000000_00000003'u64)
    @assert(Math.ror(0x80000000_00000001'u64, 65'u8) == 0xC0000000_00000000'u64)
}

#test
{
    @assert(Math.reverse(0'u8) == 0'u8)
    @assert(Math.reverse(0'u16) == 0'u16)
    @assert(Math.reverse(0'u32) == 0'u32)
    @assert(Math.reverse(0'u64) == 0'u64)

    @assert(Math.reverse(0xFF'u8) == 0xFF'u8)
    @assert(Math.reverse(0xFFFF'u16) == 0xFFFF'u16)
    @assert(Math.reverse(0xFFFFFFFF'u32) == 0xFFFFFFFF'u32)
    @assert(Math.reverse(0xFFFFFFFF_FFFFFFFF'u64) == 0xFFFFFFFF_FFFFFFFF'u64)

    @assert(Math.reverse(0x01'u8) == 0x80'u8)
    @assert(Math.reverse(0x0001'u16) == 0x8000'u16)
    @assert(Math.reverse(0x00000001'u32) == 0x80000000'u32)
    @assert(Math.reverse(0x00000000_00000001'u64) == 0x80000000_00000000'u64)

    @assert(Math.reverse(0x80'u8) == 0x01'u8)
    @assert(Math.reverse(0x8000'u16) == 0x0001'u16)
    @assert(Math.reverse(0x80000000'u32) == 0x00000001'u32)
    @assert(Math.reverse(0x80000000_00000000'u64) == 0x00000000_00000001'u64)

    @assert(Math.reverse(0x12'u8) == 0x48'u8)
    @assert(Math.reverse(0x1234'u16) == 0x2C48'u16)
    @assert(Math.reverse(0x12345678'u32) == 0x1E6A2C48'u32)
    @assert(Math.reverse(0x01234567_89ABCDEF'u64) == 0xF7B3D591_E6A2C480'u64)

    @assert(Math.byteswap(0'u16) == 0'u16)
    @assert(Math.byteswap(0'u32) == 0'u32)
    @assert(Math.byteswap(0'u64) == 0'u64)
    @assert(Math.byteswap(0xFFFF'u16) == 0xFFFF'u16)
    @assert(Math.byteswap(0xFFFFFFFF'u32) == 0xFFFFFFFF'u32)
    @assert(Math.byteswap(0xFFFFFFFF_FFFFFFFF'u64) == 0xFFFFFFFF_FFFFFFFF'u64)
    @assert(Math.byteswap(0x1234'u16) == 0x3412'u16)
    @assert(Math.byteswap(0x12345678'u32) == 0x78563412'u32)
    @assert(Math.byteswap(0x01234567_89ABCDEF'u64) == 0xEFCDAB89_67452301'u64)
}
