#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertBytesEqual(lhs, rhs: const [..] u8)->bool
{
    if lhs.count != rhs.count do
        return false

    for value, index in lhs
    {
        if value != rhs[index] do
            return false
    }

    return true
}

func pushAllocatorAcceptsNull()->bool
{
    Memory.withAllocator(null)
    {
        return Swag.getContext().allocator == null
    }

    return false
}

#test
{
    var src: [4] u8 = [1, 2, 3, 4]
    var dst: [4] u8

    Memory.copy(dst.buffer, src.buffer, #sizeof(src))
    Swag.assert(assertBytesEqual(dst, src))
    Swag.assert(Memory.compare(dst.buffer, src.buffer, #sizeof(src)) == 0)

    Memory.set(dst.buffer, 0xAB, #sizeof(dst))
    let filled: [4] u8 = [0xAB, 0xAB, 0xAB, 0xAB]
    Swag.assert(assertBytesEqual(dst, filled))

    Memory.clear(dst.buffer, #sizeof(dst))
    let zeroed: [4] u8 = [0, 0, 0, 0]
    Swag.assert(assertBytesEqual(dst, zeroed))
    Swag.assert(Memory.bytesEqual(&dst, &zeroed))
}

#test
{
    Swag.assert(Memory.align(13, 8) == 16)
    Swag.assert(Memory.align(16, 8) == 16)
    Swag.assert(Memory.align(17, 4) == 20)
    Swag.assert(Memory.align(13, 0) == #sizeof(*void) * 2)

    var buffer: [32] u8
    let misaligned = cast([*] u8) buffer.buffer + 1
    Swag.assert(cast(u64) misaligned == cast(u64) buffer.buffer + 1)
    let alignedValue = Memory.align(cast(u64) misaligned, 8)
    let aligned      = Memory.align(misaligned, 8)
    Swag.assert(cast(u64) aligned % 8 == 0)
    Swag.assert(cast(u64) aligned == alignedValue)
    Swag.assert(cast(u64) aligned >= cast(u64) misaligned)
}

#test
{
    Swag.assert(Swag.getContext().allocator != null)
    Swag.assert(pushAllocatorAcceptsNull())
    Swag.assert(Swag.getContext().allocator != null)
}
