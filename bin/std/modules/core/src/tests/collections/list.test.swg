#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertIntList(values: *List's32, expected: const [..] s32)->bool
{
    if values.count != expected.count do
        return false

    var idx: u64 = 0
    for value in values[]
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

func visitStructList(values: *List'ListStructProbe)->s32
{
    var code = 0
    for value, node in values[]
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

func visitStructListReverse(values: *List'ListStructProbe)->s32
{
    var code = 0
    for value, node in values.reversed()
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
    let tail = values.tail!
    values.insertBefore(tail, 3)

    let expected: [4] s32 = [1, 2, 3, 4]
    Swag.assert(assertIntList(&values, expected))
}

#test
{
    var values: List's32
    let first  = values.addBack(1)
    let middle = values.addBack(2)
    discard values.addBack(3)

    Swag.assert(values.count == 3)
    values.remove(middle)
    Swag.assert(values.count == 2)
    Swag.assert(values.head == first)
    Swag.assert(values.head!.next == values.tail)

    values.remove(first)
    Swag.assert(values.count == 1)
    values.remove(values.tail!)
    Swag.assert(values.isEmpty())
    Swag.assert(values.head == null and values.tail == null)
}

#test
{
    var values: List's32
    let one = values.addBack(1)
    let two = values.insertAfter(one, 2)
    discard values.insertAfter(two, 4)
    let tail = values.tail!
    values.insertBefore(tail, 3)

    var code = 0
    for value, node in values
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(node) == *ListEntry's32)
        code = code * 10 + value
    }

    Swag.assert(code == 1234)
}

#test
{
    var values: List's32
    let one = values.addBack(1)
    let two = values.insertAfter(one, 2)
    discard values.insertAfter(two, 4)
    let tail = values.tail!
    values.insertBefore(tail, 3)

    var code = 0
    for value, node in values.reversed()
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(node) == *ListEntry's32)
        code = code * 10 + value
    }

    Swag.assert(code == 4321)
}

#test
{
    var values: List's32
    values.addBack(1)
    values.addBack(2)
    values.addBack(3)

    for &value, node in values
    {
        #assert(#typeof(value) == *s32)
        #assert(#typeof(node) == *ListEntry's32)
        value[] += 10
    }

    let expected: [3] s32 = [11, 12, 13]
    Swag.assert(assertIntList(&values, expected))
}

#test
{
    var values: List'ListStructProbe
    values.addBack(ListStructProbe{value: 1})
    values.addBack(ListStructProbe{value: 2})
    values.addBack(ListStructProbe{value: 3})

    for &value in values do
        value.value += 10

    let head = values.head!
    Swag.assert(head.value.value == 11)
    Swag.assert(head.next!.value.value == 12)
    Swag.assert(values.tail!.value.value == 13)
    Swag.assert(visitStructList(&values) == 123)
    Swag.assert(visitStructListReverse(&values) == 142)
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
    let copyExpected:     [4] s32 = [1, 2, 3, 4]
    Swag.assert(assertIntList(&original, originalExpected))
    Swag.assert(assertIntList(&copy, copyExpected))
}

#test
{
    var source: List's32
    source.addBack(7)
    source.addBack(8)

    var moved: List's32
    moved = #move source

    let expected: [2] s32 = [7, 8]
    Swag.assert(source.count == 0)
    Swag.assert(source.head == null)
    Swag.assert(source.tail == null)
    Swag.assert(assertIntList(&moved, expected))
}
