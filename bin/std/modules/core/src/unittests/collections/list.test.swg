#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func assertIntList(values: &List's32, expected: const [..] s32)->bool
{
    if values.count != @countof(expected) do
        return false

    var idx: u64 = 0
    for value in values
    {
        if value != expected[idx] do
            return false
        idx += 1
    }

    return true
}

struct ListStructProbe
{
    value: s32
}

func visitStructList(values: &List'ListStructProbe)->s32
{
    var code = 0
    for value, node in values
    {
        #assert(#typeof(node) == *ListEntry'ListStructProbe)
        if value.value == 12 do
            continue

        code = code * 10 + value.value
        if value.value == 13 do
            return code
    }

    return code
}

func visitStructListReverse(values: &List'ListStructProbe)->s32
{
    var code = 0
    for #reverse value, node in values
    {
        #assert(#typeof(node) == *ListEntry'ListStructProbe)
        code = code * 10 + value.value
        if value.value == 12 do
            return code
    }

    return code
}

#test
{
    var values: List's32
    values.addBack(2)
    values.addFront(1)
    values.addBack(4)
    values.insertBefore(values.tail, 3)

    let expected: [4] s32 = [1, 2, 3, 4]
    @assert(assertIntList(&values, expected))
}

#test
{
    var values: List's32
    let one = values.addBack(1)
    let two = values.insertAfter(one, 2)
    discard values.insertAfter(two, 4)
    values.insertBefore(values.tail, 3)

    var code = 0
    for value, node in values
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(node) == *ListEntry's32)
        code = code * 10 + value
    }

    @assert(code == 1234)
}

#test
{
    var values: List's32
    let one = values.addBack(1)
    let two = values.insertAfter(one, 2)
    discard values.insertAfter(two, 4)
    values.insertBefore(values.tail, 3)

    var code = 0
    for #reverse value, node in values
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(node) == *ListEntry's32)
        code = code * 10 + value
    }

    @assert(code == 4321)
}

#test
{
    var values: List's32
    values.addBack(1)
    values.addBack(2)
    values.addBack(3)

    for &value, node in values
    {
        #assert(#typeof(value) == #type &s32)
        #assert(#typeof(node) == *ListEntry's32)
        value += 10
    }

    let expected: [3] s32 = [11, 12, 13]
    @assert(assertIntList(&values, expected))
}

#test
{
    var values: List'ListStructProbe
    values.addBack(ListStructProbe{value: 1})
    values.addBack(ListStructProbe{value: 2})
    values.addBack(ListStructProbe{value: 3})

    for &value in values do
        value.value += 10

    @assert(values.head.value.value == 11)
    @assert(values.head.next.value.value == 12)
    @assert(values.tail.value.value == 13)
    @assert(visitStructList(&values) == 123)
    @assert(visitStructListReverse(&values) == 142)
}

#test
{
    var original: List's32
    original.addBack(1)
    original.addBack(2)
    original.addBack(3)

    var copy = original
    copy.addBack(4)

    let originalExpected: [3] s32 = [1, 2, 3]
    let copyExpected: [4] s32 = [1, 2, 3, 4]
    @assert(assertIntList(&original, originalExpected))
    @assert(assertIntList(&copy, copyExpected))
}

#test
{
    var source: List's32
    source.addBack(7)
    source.addBack(8)

    var moved: List's32
    moved = #move source

    let expected: [2] s32 = [7, 8]
    @assert(source.count == 0)
    @assert(source.head == null)
    @assert(source.tail == null)
    @assert(assertIntList(&moved, expected))
}
