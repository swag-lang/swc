#global fileprivate
using Swag

#test
{
    @assert(Math.isPowerOf2(1'u32))
    @assert(Math.isPowerOf2(1024'u32))
    @assert(!Math.isPowerOf2(0'u32))
    @assert(!Math.isPowerOf2(1023'u32))
    @assert(Math.make64(0x12345678'u32, 0x9abcdef0'u32) == 0x123456789abcdef0'u64)
}
