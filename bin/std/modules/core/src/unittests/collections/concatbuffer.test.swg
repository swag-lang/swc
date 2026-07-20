#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func buildConcatBuffer()->ConcatBuffer
{
    var result: retval
    result.setBucketSize(4)

    let first: [3] u8  = [1, 2, 3]
    let second: [3] u8 = [4, 5, 6]
    let third: [2] u8  = [7, 8]

    result.addBytes(first)
    result.addBytes(second)
    result.addBytes(third)
    return result
}

func frontBucketCount(buffer: const &ConcatBuffer)->u64
{
    for bucket in buffer do
        return bucket.count

    return 0
}

func backBucketCount(buffer: const &ConcatBuffer)->u64
{
    for #reverse bucket in buffer do
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
    for #reverse bucket in buffer do
        reverseCode = reverseCode * 10 + bucket.count

    @assert(forwardCode == 332)
    @assert(reverseCode == 233)
}

#test
{
    let buffer = buildConcatBuffer()

    @assert(frontBucketCount(buffer) == 3)
    @assert(backBucketCount(buffer) == 2)
}

#test
{
    let storage = cast(#nonull [*] u8) Memory.alloc(8)
    var buffer: ConcatBuffer
    buffer.setFirstBucket(@mkslice(storage, 8))
    buffer.addBytes(cast(#nonull const [..] u8) "abc")

    let text = buffer.moveToString()
    storage[0] = 'z''u8
    @assert(text.toString() == "abc")
}
