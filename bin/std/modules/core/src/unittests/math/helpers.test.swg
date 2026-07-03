#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

#test
{
    @assert(Math.clamp(5, 0, 10) == 5)
    @assert(Math.clamp(-1, 0, 10) == 0)
    @assert(Math.clamp(11, 0, 10) == 10)
    @assert(Math.clamp(2.5'f32, 3'f32, 4'f32) == 3'f32)

    @assert(Math.min(5, 2) == 2)
    @assert(Math.max(5, 2) == 5)
    @assert(Math.min(5, 2, -1) == -1)
    @assert(Math.max(5, 2, -1) == 5)
    @assert(Math.min(5, 2, -1, 9) == -1)
    @assert(Math.max(5, 2, -1, 9) == 9)
}

#test
{
    @assert(Math.bigEndianToNative(0x1234'u16) == 0x3412'u16)
    @assert(Math.nativeToBigEndian(0x12345678'u32) == 0x78563412'u32)
    @assert(Math.littleEndianToNative(0x12345678'u32) == 0x12345678'u32)
}
