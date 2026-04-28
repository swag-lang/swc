#global skip(test)
#global fileprivate
using Swag

#test
{
    @assert(Math.leadingZeros(0x10'u32) == 27'u32)
    @assert(Math.trailingZeros(0x10'u32) == 4'u32)
    @assert(Math.countOnes(0xA5'u8) == 4'u8)
    @assert(Math.rol(0x12'u8, 4'u8) == 0x21'u8)
    @assert(Math.ror(0x12'u8, 4'u8) == 0x21'u8)
    @assert(Math.reverse(0x12'u8) == 0x48'u8)
    @assert(Math.byteswap(0x1234'u16) == 0x3412'u16)
}
