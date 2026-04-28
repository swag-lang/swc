#global skip(test)
#global fileprivate
using Swag

#test
{
    @assert(Math.isPowerOf2(1'u32))
    @assert(Math.isPowerOf2(1024'u32))
    @assert(!Math.isPowerOf2(0'u32))
    @assert(!Math.isPowerOf2(1023'u32))
    @assert(Math.roundUpToPowerOf2(0'u32) == 1'u32)
    @assert(Math.roundUpToPowerOf2(1'u32) == 1'u32)
    @assert(Math.roundUpToPowerOf2(2'u32) == 2'u32)
    @assert(Math.roundUpToPowerOf2(3'u32) == 4'u32)
    @assert(Math.roundUpToPowerOf2(1024'u32) == 1024'u32)
    @assert(Math.roundUpToPowerOf2(1025'u32) == 2048'u32)
    @assert(Math.roundUpToPowerOf2(1'u64) == 1'u64)
    @assert(Math.roundUpToPowerOf2(1024'u64) == 1024'u64)
    @assert(Math.make64(0x12345678'u32, 0x9abcdef0'u32) == 0x123456789abcdef0'u64)
}
