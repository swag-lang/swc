#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func buildConcatBuffer()->ConcatBuffer
{
    var result: #returntype
    result.setBucketSize(4)

    let first:  [3] u8 = [1, 2, 3]
    let second: [3] u8 = [4, 5, 6]
    let third:  [2] u8 = [7, 8]

    result.addBytes(first)
    result.addBytes(second)
    result.addBytes(third)
    return result
}

func frontBucketCount(buffer: ConcatBuffer)->u64
{
    for bucket in buffer do
        return bucket.count

    return 0
}

func backBucketCount(buffer: ConcatBuffer)->u64
{
    for bucket in buffer.reversed() do
        return bucket.count

    return 0
}

func inspectConcatBuffer(buffer: ConcatBuffer)->bool
{
    let bytes = unwrap buffer.toSlice()
    return buffer.count() == 3 and
           ConcatBuffer.offsetOf(buffer.position()) == 3 and
           Memory.compare(bytes.buffer, "abc".buffer, 3) == 0
}

#test
{
    var buffer: ConcatBuffer
    buffer.setBucketSize(4)
    buffer.addBytes("abcd")
    buffer.addBytes("efgh")
    buffer.setPosition({})
    buffer.advance(2)
    let saved = buffer.position()
    let bytes = buffer.toArray()
    Swag.require(bytes.count == 8)
    Swag.require(Memory.compare(bytes.storage(), "abcdefgh".buffer, 8) == 0)
    Swag.require(buffer.position().bucket == saved.bucket)
    Swag.require(buffer.position().pointer == saved.pointer)
    Swag.require(buffer.toSlice() == null)
    buffer.release()
    Swag.require(Memory.compare(bytes.storage(), "abcdefgh".buffer, 8) == 0)
}

#test
{
    var allocator: Swag.Allocator
    allocator.setup()
    allocator.configure(false, false, false, false, false)
    let backing: Swag.IAllocator = &allocator
    var buffer:  ConcatBuffer
    scope
    {
        let empty = buffer.toArray(backing)
        Swag.require(empty.isEmpty() and allocator.stats().countAlloc == 0)
        buffer.setBucketSize(4)
        buffer.addBytes("first")
        buffer.addBytes("second")
        let bytes = buffer.toArray(backing)
        Swag.require(bytes.allocator == backing)
        Swag.require(bytes.count == 11 and allocator.stats().countAlloc == 1)
    }

    Swag.require(allocator.stats().countAlloc == 0)
}

#test
{
    var buffer: ConcatBuffer
    buffer.addBytes("abc")
    Swag.require(inspectConcatBuffer(buffer))
}

#test
{
    var source: ConcatBuffer
    source.setBucketSize(4)
    source.setFirstBucket(Swag.makeSlice(cast([*] u8, Memory.alloc(4)), 4))
    source.addBytes("abcd")
    source.addBytes("efgh")
    source.setPosition({})
    source.advance(2)
    var moved = #move source
    moved.addNative('X'u8)
    Swag.require(moved.toString() == "abXdefgh")
    moved.setPosition({})
    moved.advance(8)
    moved.addBytes("ij")
    Swag.require(moved.toString() == "abXdefghij")
}

#test
{
    let buffer = buildConcatBuffer()

    var forwardCode: u64 = 0
    for bucket in buffer do
        forwardCode = forwardCode * 10 + bucket.count

    var reverseCode: u64 = 0
    for bucket in buffer.reversed() do
        reverseCode = reverseCode * 10 + bucket.count

    Swag.require(forwardCode == 332)
    Swag.require(reverseCode == 233)
}

#test
{
    let buffer = buildConcatBuffer()

    Swag.require(frontBucketCount(buffer) == 3)
    Swag.require(backBucketCount(buffer) == 2)
}

#test
{
    let storage = cast([*] u8, Memory.alloc(8))
    var buffer: ConcatBuffer
    buffer.setFirstBucket(Swag.makeSlice(storage, 8))
    buffer.addBytes(cast(const [..] u8, "abc"))

    let text = buffer.moveToString()
    storage[0] = 'z'u8
    Swag.require(text.toString() == "abc")
}

#test
{
    var buffer = buildConcatBuffer()
    buffer.release()
    Swag.require(buffer.count() == 0)
    Swag.require(buffer.position().bucket == null)
    buffer.release()
    buffer.addBytes("reused")
    Swag.require(buffer.toString() == "reused")
    Swag.require(buffer.granularity == 4)
}

#test
{
    var buffer: ConcatBuffer
    Swag.require(buffer.toSlice() == null)
    Swag.require(buffer.moveToString().isEmpty())
    buffer.addBytes("after empty extraction")
    Swag.require(buffer.toString() == "after empty extraction")
}

#test
{
    var buffer: ConcatBuffer
    buffer.addBytes("owned")
    let text = buffer.moveToString()
    Swag.require(text == "owned")
    Swag.require(buffer.count() == 0)
    Swag.require(buffer.position().bucket == null)
    buffer.addBytes("new storage")
    Swag.require(buffer.toString() == "new storage")
    Swag.require(text == "owned")
}

// A linear active buffer can still own unused buckets retained by clear().
#test
{
    var allocator: Swag.Allocator
    allocator.setup()
    allocator.configure(false, false, false, false, false)
    let backing: Swag.IAllocator = &allocator
    scope
    {
        var buffer: ConcatBuffer
        buffer.allocator = backing
        buffer.setBucketSize(4)
        buffer.addBytes("first")
        buffer.addBytes("second")
        buffer.addBytes("third")
        buffer.clear()
        buffer.addBytes("kept")

        let text = buffer.moveToString()
        Swag.require(text == "kept")
        Swag.require(allocator.stats().countAlloc == 1)
        Swag.require(buffer.allocator == backing)
        buffer.release()
    }

    Swag.require(allocator.stats().countAlloc == 0)
}

#test
{
    var buffer: ConcatBuffer
    buffer.setBucketSize(4)
    buffer.addBytes("ab")
    let saved = buffer.position()
    buffer.addBytes("cd")
    buffer.addBytes("efgh")
    buffer.setPosition(saved)

    let restored = buffer.position()
    Swag.require(restored.bucket == saved.bucket)
    Swag.require(restored.pointer == saved.pointer)
    Swag.require(ConcatBuffer.offsetOf(restored) == 2)
    buffer.addNative('X'u8)
    Swag.require(ConcatBuffer.offsetOf(buffer.position()) == 3)
    Swag.require(buffer.toString() == "abXdefgh")
}

#test
{
    var buffer: ConcatBuffer
    buffer.setBucketSize(4)
    let first = buffer.reserveInPlace(4)
    Memory.copy(first, "abcd".buffer, 4)
    let second = buffer.reserveInPlace(8)
    Memory.copy(second, "efghijkl".buffer, 8)
    Swag.require(buffer.count() == 12)
    Swag.require(buffer.toString() == "abcdefghijkl")
}

#test
{
    var buffer: ConcatBuffer
    buffer.setBucketSize(4)
    buffer.addBytes("ab")
    let saved = buffer.position()
    buffer.addBytes("cd")
    buffer.addBytes("efgh")
    buffer.setPosition(saved)
    let writable = buffer.reserveInPlace(8)
    Memory.copy(writable, "12345678".buffer, 8)
    Swag.require(buffer.count() == 10)
    Swag.require(ConcatBuffer.offsetOf(buffer.position()) == 10)
    Swag.require(buffer.toString() == "ab12345678")
}

// A retained bucket is reusable capacity, never part of the logical input.
#test
{
    var buffer: ConcatBuffer
    buffer.setBucketSize(4)
    buffer.addBytes("abcd")
    buffer.addBytes("efgh")
    buffer.clear()
    buffer.addBytes("xy")
    buffer.setPosition({})
    buffer.addBytes("123456", false)
    Swag.require(buffer.count() == 6)
    Swag.require(buffer.toString() == "123456")
}

#test
{
    var buffer: ConcatBuffer
    buffer.setBucketSize(4)
    buffer.addBytes("abcd")
    buffer.addBytes("efgh")
    buffer.clear()
    buffer.addBytes("xy")
    buffer.setPosition({})
    buffer.advance(6)
    Swag.require(buffer.count() == 6)
    Swag.require(ConcatBuffer.offsetOf(buffer.position()) == 6)
    buffer.addBytes("z")
    Swag.require(buffer.count() == 7)
}

#test
{
    var buffer: ConcatBuffer
    buffer.setPosition({})
    buffer.truncate({})
    buffer.advance(0)
    Swag.require(buffer.count() == 0)
    buffer.addBytes("usable")
    Swag.require(buffer.toString() == "usable")
}

#test
{
    let storage = cast([*] u8, Memory.alloc(8))
    var source: ConcatBuffer
    source.setFirstBucket(Swag.makeSlice(storage, 8))
    source.addBytes("abc")
    var moved: ConcatBuffer
    moved = #move source
    Swag.require(source.count() == 0)
    Swag.require(moved.toString() == "abc")
    moved.addBytes("d")
    Swag.require(moved.toString() == "abcd")
}

#test
{
    let buffer = buildConcatBuffer()
    var visits = 0
    for bucket in buffer
    {
        visits += 1
        Swag.require(visits <= 3)
        if visits == 1 do
            continue
        Swag.require(bucket.count > 0)
    }

    Swag.require(visits == 3)
    visits = 0
    for bucket in buffer.reversed()
    {
        visits += 1
        Swag.require(visits <= 3)
        if visits == 1 do
            continue
        Swag.require(bucket.count > 0)
    }

    Swag.require(visits == 3)
}

#test
{
    var buffer: ConcatBuffer
    buffer.addBytes("a")
    buffer.setPosition({})
    buffer.addNative('b'u8)
    buffer.addBytes("c")
    Swag.require(buffer.toString() == "bc")
}

#test
{
    var buffer: ConcatBuffer
    buffer.setBucketSize(4)
    buffer.addBytes("tiny")
    var text  = buffer.moveToString()
    var moved = #move text
    Swag.require(moved == "tiny")
    Swag.require(moved.storage()[moved.count] == 0)
    Swag.require(buffer.count() == 0)
    moved.append(" again")
    Swag.require(moved == "tiny again")
}

#test
{
    var buffer: ConcatBuffer
    buffer.setBucketSize(32)
    buffer.addBytes("0123456789abcdef0123456789abcdef")
    let text = buffer.moveToString()
    Swag.require(text == "0123456789abcdef0123456789abcdef")
    Swag.require(text.capacity > text.count)
    Swag.require(text.storage()[text.count] == 0)
}

#test
{
    var allocator: Swag.Allocator
    allocator.setup()
    allocator.configure(false, false, false, false, false)
    let backing: Swag.IAllocator = &allocator
    var buffer:  ConcatBuffer
    scope
    {
        let context  = Swag.getContext()
        let original = context.allocator
        context.allocator = backing
        defer context.allocator = original
        buffer.setFirstBucket(Swag.makeSlice(cast([*] u8, Memory.alloc(8)), 8))
    }

    let captured = buffer.allocator == backing
    buffer.allocator = backing
    buffer.addBytes("owned")
    buffer.release()
    Swag.require(captured)
    Swag.require(allocator.stats().countAlloc == 0)
}

#test
{
    var buffer: ConcatBuffer
    buffer.setBucketSize(4)
    buffer.addBytes("abcd")
    buffer.addBytes("efgh")
    buffer.setPosition({})
    buffer.advance(2)
    buffer.addBytes("12345")
    Swag.require(buffer.toString() == "ab12345h")
    Swag.require(ConcatBuffer.offsetOf(buffer.position()) == 7)
    buffer.addNative('X'u8)
    buffer.addBytes("!")
    Swag.require(buffer.toString() == "ab12345X!")
}

#test
{
    var buffer: ConcatBuffer
    buffer.setBucketSize(4)
    buffer.addBytes("abcd")
    let bytes = unwrap buffer.toSlice()
    buffer.addBytes("efgh")
    buffer.setPosition({})
    buffer.advance(2)
    buffer.addBytes(bytes)
    Swag.require(buffer.toString() == "ababcdgh")
}

#test
{
    var buffer: ConcatBuffer
    buffer.setBucketSize(4)
    buffer.addBytes("ab")
    let first = buffer.position().bucket
    buffer.setPosition({})
    buffer.advance(1)
    let bytes = buffer.reserveInPlace(3)
    Memory.copy(bytes, "xyz".buffer, 3)
    Swag.require(buffer.position().bucket == first)
    Swag.require(buffer.toString() == "axyz")
    let saved = buffer.position()
    discard buffer.reserveInPlace(0)
    Swag.require(buffer.position().bucket == saved.bucket)
    Swag.require(buffer.position().pointer == saved.pointer)
}
