#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

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
    Swag.require(Slice.equals(dst, src))
    Swag.require(Memory.compare(dst.buffer, src.buffer, #sizeof(src)) == 0)

    Memory.set(dst.buffer, 0xAB, #sizeof(dst))
    let filled: [4] u8 = [0xAB, 0xAB, 0xAB, 0xAB]
    Swag.require(Slice.equals(dst, filled))

    Memory.clear(dst.buffer, #sizeof(dst))
    let zeroed: [4] u8 = [0, 0, 0, 0]
    Swag.require(Slice.equals(dst, zeroed))
    Swag.require(Memory.bytesEqual(&dst, &zeroed))
}

#test
{
    Swag.require(Memory.align(13, 8) == 16)
    Swag.require(Memory.align(16, 8) == 16)
    Swag.require(Memory.align(17, 4) == 20)
    Swag.require(Memory.align(13, 0) == #sizeof(*void) * 2)

    var buffer: [32] u8
    let misaligned = cast([*] u8, buffer.buffer) + 1
    Swag.require(cast(u64, misaligned) == cast(u64, buffer.buffer) + 1)
    let alignedValue = Memory.align(cast(u64, misaligned), 8)
    let aligned      = Memory.align(misaligned, 8)
    Swag.require(cast(u64, aligned) % 8 == 0)
    Swag.require(cast(u64, aligned) == alignedValue)
    Swag.require(cast(u64, aligned) >= cast(u64, misaligned))
}

#test
{
    Swag.require(Memory.align(Swag.U64.Max - 7, 8) == Swag.U64.Max - 7)
    let result = Swag.catchPanic(func||() { discard Memory.align(Swag.U64.Max, 8) })
    Swag.require(result.raised)
    Swag.require(result.message() == "aligned value exceeds addressable range")
}

#test
{
    let result = Swag.catchPanic(func||() { discard Memory.align(13, 3) })
    Swag.require(result.raised)
    Swag.require(result.message() == "alignment must be a power of two")
}

#test
{
    let count     = Swag.U64.Max / #sizeof(s32) + 1
    let allocated = Swag.catchPanic(func|count|() { discard Memory.new's32(count) })
    Swag.require(allocated.raised)
    Swag.require(allocated.message() == "memory region size exceeds addressable range")

    let value = Memory.new's32()
    defer Memory.delete(value)
    let released = Swag.catchPanic(func|value, count|() { Memory.delete(value, count) })
    Swag.require(released.raised)
    Swag.require(released.message() == "memory region size exceeds addressable range")
}

#test
{
    Swag.require(Swag.getContext().allocator != null)
    Swag.require(pushAllocatorAcceptsNull())
    Swag.require(Swag.getContext().allocator != null)
}

// Zero-byte operations still take valid addresses and leave their storage unchanged.
#test
{
    var source: [4] u8 = [1, 2, 3, 4]
    var target: [4] u8 = [5, 6, 7, 8]
    Memory.copy(target, source, 0)
    Memory.copyOverlapping(target, target, 0)
    Memory.set(target, 0xFF, 0)
    Memory.clear(target, 0)
    Swag.require(Memory.compare(target, source, 0) == 0)
    Swag.require(target == [5, 6, 7, 8])
}

#test
{
    var bytes: [6] u8 = [1, 2, 3, 4, 5, 6]
    Memory.copyOverlapping(bytes.buffer + 1, bytes.buffer, 5)
    Swag.require(bytes == [1, 1, 2, 3, 4, 5])

    bytes = [1, 2, 3, 4, 5, 6]
    Memory.copyOverlapping(bytes.buffer, bytes.buffer + 1, 5)
    Swag.require(bytes == [2, 3, 4, 5, 6, 6])
}

#test
{
    let left:  [3] u8 = [0x7F, 0xFF, 0x00]
    let right: [3] u8 = [0x80, 0x00, 0x00]
    Swag.require(Memory.compare(left.buffer, right.buffer, 1) < 0)
    Swag.require(Memory.compare(right.buffer, left.buffer, 1) > 0)

    let lower: [3] u8 = [0x12, 0x34, 0x56]
    let upper: [3] u8 = [0x12, 0x34, 0x57]
    Swag.require(Memory.compare(lower.buffer, upper.buffer, 0) == 0)
    Swag.require(Memory.compare(lower.buffer, upper.buffer, 1) == 0)
    Swag.require(Memory.compare(lower.buffer, upper.buffer, 2) == 0)
    Swag.require(Memory.compare(lower.buffer, upper.buffer, 3) < 0)
    Swag.require(Memory.compare(upper.buffer, lower.buffer, 3) > 0)
}
