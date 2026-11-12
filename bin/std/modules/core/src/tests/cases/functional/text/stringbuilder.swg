#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertBuilderString(value: String, expected: string)->bool
{
    let text = value.toString()
    return value == expected and
           value.count == expected.count and
           text.count == expected.count and
           Memory.compare(text.buffer, expected.buffer, expected.count) == 0
}

#test
{
    var builder: StrConv.StringBuilder
    builder.appendString("abc")
    builder.zeroTerminate()

    Swag.require(builder.count() == 3)
    Swag.require(assertBuilderString(builder.toString(), "abc"))

    builder.zeroTerminate()
    Swag.require(builder.count() == 3)

    builder.appendString("def")
    Swag.require(builder.count() == 6)
    Swag.require(assertBuilderString(builder.moveToString(), "abcdef"))

    var exactBucket: StrConv.StringBuilder
    exactBucket.setBucketSize(4)
    exactBucket.appendString("abcd")
    exactBucket.zeroTerminate()
    let bytes = unwrap exactBucket.buffer.toSlice()
    Swag.require(exactBucket.count() == 4)
    Swag.require(bytes.buffer[4] == 0)
}

#test
{
    var allocator: Swag.Allocator
    allocator.setup()
    allocator.configure(false, false, false, false, false)
    let backing: Swag.IAllocator = &allocator

    scope
    {
        var builder: StrConv.StringBuilder
        builder.buffer.allocator = backing
        builder.setBucketSize(8)
        builder.appendString("first payload that spans buckets")
        let allocations = allocator.stats().countAlloc
        Swag.require(allocations > 0)

        builder.clear()
        Swag.require(builder.count() == 0)
        builder.appendString("reuse")
        Swag.require(builder.count() == 5)
        Swag.require(allocator.stats().countAlloc == allocations)
        Swag.require(assertBuilderString(builder.toString(), "reuse"))
    }

    Swag.require(allocator.stats().countAlloc == 0)
}
