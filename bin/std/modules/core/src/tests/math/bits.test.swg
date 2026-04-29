#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

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

    @assert(Math.countOnes(0xff'u8) == 8'u8)
    @assert(Math.countOnes(0xffff'u16) == 16'u16)
    @assert(Math.countOnes(0xffffffff'u32) == 32'u32)
    @assert(Math.countOnes(0xffffffff_ffffffff'u64) == 64'u64)

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
    @assert(Math.ror(0x81'u8, 1'u8) == 0xc0'u8)
    @assert(Math.rol(0x12'u8, 4'u8) == 0x21'u8)
    @assert(Math.ror(0x12'u8, 4'u8) == 0x21'u8)
    @assert(Math.rol(0x81'u8, 8'u8) == 0x81'u8)
    @assert(Math.ror(0x81'u8, 8'u8) == 0x81'u8)

    @assert(Math.rol(0x8001'u16, 0'u8) == 0x8001'u16)
    @assert(Math.ror(0x8001'u16, 0'u8) == 0x8001'u16)
    @assert(Math.rol(0x8001'u16, 1'u8) == 0x0003'u16)
    @assert(Math.ror(0x8001'u16, 1'u8) == 0xc000'u16)
    @assert(Math.rol(0x1234'u16, 8'u8) == 0x3412'u16)
    @assert(Math.ror(0x1234'u16, 8'u8) == 0x3412'u16)
    @assert(Math.rol(0x8001'u16, 16'u8) == 0x8001'u16)
    @assert(Math.ror(0x8001'u16, 16'u8) == 0x8001'u16)

    @assert(Math.rol(0x80000001'u32, 0'u8) == 0x80000001'u32)
    @assert(Math.ror(0x80000001'u32, 0'u8) == 0x80000001'u32)
    @assert(Math.rol(0x80000001'u32, 1'u8) == 0x00000003'u32)
    @assert(Math.ror(0x80000001'u32, 1'u8) == 0xc0000000'u32)
    @assert(Math.rol(0x12345678'u32, 8'u8) == 0x34567812'u32)
    @assert(Math.ror(0x12345678'u32, 8'u8) == 0x78123456'u32)
    @assert(Math.rol(0x80000001'u32, 32'u8) == 0x80000001'u32)
    @assert(Math.ror(0x80000001'u32, 32'u8) == 0x80000001'u32)

    @assert(Math.rol(0x80000000_00000001'u64, 0'u8) == 0x80000000_00000001'u64)
    @assert(Math.ror(0x80000000_00000001'u64, 0'u8) == 0x80000000_00000001'u64)
    @assert(Math.rol(0x80000000_00000001'u64, 1'u8) == 0x00000000_00000003'u64)
    @assert(Math.ror(0x80000000_00000001'u64, 1'u8) == 0xc0000000_00000000'u64)
    @assert(Math.rol(0x01234567_89abcdef'u64, 8'u8) == 0x23456789_abcdef01'u64)
    @assert(Math.ror(0x01234567_89abcdef'u64, 8'u8) == 0xef012345_6789abcd'u64)
    @assert(Math.rol(0x80000000_00000001'u64, 64'u8) == 0x80000000_00000001'u64)
    @assert(Math.ror(0x80000000_00000001'u64, 64'u8) == 0x80000000_00000001'u64)
}

#test
{
    @assert(Math.reverse(0'u8) == 0'u8)
    @assert(Math.reverse(0'u16) == 0'u16)
    @assert(Math.reverse(0'u32) == 0'u32)
    @assert(Math.reverse(0'u64) == 0'u64)

    @assert(Math.reverse(0xff'u8) == 0xff'u8)
    @assert(Math.reverse(0xffff'u16) == 0xffff'u16)
    @assert(Math.reverse(0xffffffff'u32) == 0xffffffff'u32)
    @assert(Math.reverse(0xffffffff_ffffffff'u64) == 0xffffffff_ffffffff'u64)

    @assert(Math.reverse(0x01'u8) == 0x80'u8)
    @assert(Math.reverse(0x0001'u16) == 0x8000'u16)
    @assert(Math.reverse(0x00000001'u32) == 0x80000000'u32)
    @assert(Math.reverse(0x00000000_00000001'u64) == 0x80000000_00000000'u64)

    @assert(Math.reverse(0x80'u8) == 0x01'u8)
    @assert(Math.reverse(0x8000'u16) == 0x0001'u16)
    @assert(Math.reverse(0x80000000'u32) == 0x00000001'u32)
    @assert(Math.reverse(0x80000000_00000000'u64) == 0x00000000_00000001'u64)

    @assert(Math.reverse(0x12'u8) == 0x48'u8)
    @assert(Math.reverse(0x1234'u16) == 0x2c48'u16)
    @assert(Math.reverse(0x12345678'u32) == 0x1e6a2c48'u32)
    @assert(Math.reverse(0x01234567_89abcdef'u64) == 0xf7b3d591_e6a2c480'u64)

    @assert(Math.byteswap(0'u16) == 0'u16)
    @assert(Math.byteswap(0'u32) == 0'u32)
    @assert(Math.byteswap(0'u64) == 0'u64)
    @assert(Math.byteswap(0xffff'u16) == 0xffff'u16)
    @assert(Math.byteswap(0xffffffff'u32) == 0xffffffff'u32)
    @assert(Math.byteswap(0xffffffff_ffffffff'u64) == 0xffffffff_ffffffff'u64)
    @assert(Math.byteswap(0x1234'u16) == 0x3412'u16)
    @assert(Math.byteswap(0x12345678'u32) == 0x78563412'u32)
    @assert(Math.byteswap(0x01234567_89abcdef'u64) == 0xefcdab89_67452301'u64)
}
