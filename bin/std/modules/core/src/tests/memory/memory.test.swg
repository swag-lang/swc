#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

func assertBytesEqual(lhs, rhs: const [..] u8)->bool
{
    if @countof(lhs) != @countof(rhs) do
        return false

    foreach value, index in lhs
    {
        if value != rhs[index] do
            return false
    }

    return true
}

func pushAllocatorAcceptsNull()->bool
{
    Memory.pushAllocator(null)
    {
        return @getcontext().allocator == null
    }

    return false
}

#test
{
    var src: [4] u8 = [1, 2, 3, 4]
    var dst: [4] u8

    Memory.copy(@dataof(dst), @dataof(src), #sizeof(src))
    @assert(assertBytesEqual(dst, src))
    @assert(Memory.compare(@dataof(dst), @dataof(src), #sizeof(src)) == 0)

    Memory.set(@dataof(dst), 0xAB, #sizeof(dst))
    let filled: [4] u8 = [0xAB, 0xAB, 0xAB, 0xAB]
    @assert(assertBytesEqual(dst, filled))

    Memory.clear(@dataof(dst), #sizeof(dst))
    let zeroed: [4] u8 = [0, 0, 0, 0]
    @assert(assertBytesEqual(dst, zeroed))
    @assert(Memory.equals(&dst, &zeroed))
}

#test
{
    @assert(Memory.align(13, 8) == 16)
    @assert(Memory.align(16, 8) == 16)
    @assert(Memory.align(17, 4) == 20)
    @assert(Memory.align(13, 0) == #sizeof(*void) * 2)

    var buffer: [32] u8
    let misaligned = cast([*] u8) @dataof(buffer) + 1
    @assert(cast(u64) misaligned == cast(u64) @dataof(buffer) + 1)
    let alignedValue = Memory.align(cast(u64) misaligned, 8)
    let aligned = Memory.align(misaligned, 8)
    @assert(cast(u64) aligned % 8 == 0)
    @assert(cast(u64) aligned == alignedValue)
    @assert(cast(u64) aligned >= cast(u64) misaligned)
}

#test
{
    @assert(@getcontext().allocator != null)
    @assert(pushAllocatorAcceptsNull())
    @assert(@getcontext().allocator != null)
}
