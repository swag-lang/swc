#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func buildConcatBuffer()->ConcatBuffer
{
    var result: retval
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

#test
{
    let buffer = buildConcatBuffer()

    var forwardCode: u64 = 0
    for bucket in buffer do
        forwardCode = forwardCode * 10 + bucket.count

    var reverseCode: u64 = 0
    for bucket in buffer.reversed() do
        reverseCode = reverseCode * 10 + bucket.count

    Swag.assert(forwardCode == 332)
    Swag.assert(reverseCode == 233)
}

#test
{
    let buffer = buildConcatBuffer()

    Swag.assert(frontBucketCount(buffer) == 3)
    Swag.assert(backBucketCount(buffer) == 2)
}

#test
{
    let storage = cast([*] u8) Memory.alloc(8)
    var buffer: ConcatBuffer
    buffer.setFirstBucket(Swag.makeSlice(storage, 8))
    buffer.addBytes(cast(const [..] u8) "abc")

    let text = buffer.moveToString()
    storage[0] = 'z'u8
    Swag.assert(text.toString() == "abc")
}
