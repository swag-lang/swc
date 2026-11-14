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

func assertConstReversedListBorrows(values: const *List's32)->s32
{
    var total = 0
    for &item, node, index in values[].reversed()
    {
        #assert(#typeof(item) == const *s32)
        #assert(#typeof(node) == const *ListEntry's32)
        Swag.require(node.value == item[])
        total += item[] + cast(s32, index)
    }
    return total
}

#test
{
    var values: List's32
    values.addBack(2)
    values.addFront(1)
    values.addBack(4)
    let tail = unwrap values.tail
    values.insertBefore(tail, 3)

    let expected: [4] s32 = [1, 2, 3, 4]
    Swag.require(assertIntList(&values, expected))
}

#test
{
    var values: List's32
    let first  = values.addBack(1)
    let middle = values.addBack(2)
    discard values.addBack(3)

    Swag.require(values.count == 3)
    values.remove(middle)
    Swag.require(values.count == 2)
    Swag.require(values.head == first)
    Swag.require(values.head!.next == values.tail)

    values.remove(first)
    Swag.require(values.count == 1)
    values.remove(unwrap values.tail)
    Swag.require(values.isEmpty())
    Swag.require(values.head == null and values.tail == null)
}

#test
{
    var values: List's32
    let one = values.addBack(1)
    let two = values.insertAfter(one, 2)
    discard values.insertAfter(two, 4)
    let tail = unwrap values.tail
    values.insertBefore(tail, 3)

    var code = 0
    for value, node in values
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(node) == *ListEntry's32)
        code = code * 10 + value
    }

    Swag.require(code == 1234)
}

#test
{
    var values: List's32
    let one = values.addBack(1)
    let two = values.insertAfter(one, 2)
    discard values.insertAfter(two, 4)
    let tail = unwrap values.tail
    values.insertBefore(tail, 3)

    var code = 0
    for value, node in values.reversed()
    {
        #assert(#typeof(value) == s32)
        #assert(#typeof(node) == *ListEntry's32)
        code = code * 10 + value
    }

    Swag.require(code == 4321)
}

#test
{
    var values: List's32
    values.addBack(1)
    values.addBack(2)
    values.addBack(3)

    Swag.require(assertConstReversedListBorrows(&values) == 9)

    for &value, node in values
    {
        #assert(#typeof(value) == *s32)
        #assert(#typeof(node) == *ListEntry's32)
        value[] += 10
    }

    let expected: [3] s32 = [11, 12, 13]
    Swag.require(assertIntList(&values, expected))
}

#test
{
    var values: List'ListStructProbe
    values.addBack({value: 1})
    values.addBack({value: 2})
    values.addBack({value: 3})

    for &value in values do
        value.value += 10

    let head = unwrap values.head
    Swag.require(head.value.value == 11)
    Swag.require(head.next!.value.value == 12)
    Swag.require(values.tail!.value.value == 13)
    Swag.require(visitStructList(&values) == 123)
    Swag.require(visitStructListReverse(&values) == 142)
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
    Swag.require(assertIntList(&original, originalExpected))
    Swag.require(assertIntList(&copy, copyExpected))
}

#test
{
    var source: List's32
    source.addBack(7)
    source.addBack(8)

    var moved: List's32
    moved = #move source

    let expected: [2] s32 = [7, 8]
    Swag.require(source.isEmpty())
    Swag.require(source.head == null)
    Swag.require(source.tail == null)
    Swag.require(assertIntList(&moved, expected))
}

#test
{
    var values: List's32
    values.addBack(1)
    values.addBack(2)
    values.addBack(3)

    values.clear()
    Swag.require(values.isEmpty())
    Swag.require(values.count == 0)
    Swag.require(values.head == null and values.tail == null)

    values.addFront(4)
    values.addBack(5)
    let expected: [2] s32 = [4, 5]
    Swag.require(assertIntList(&values, expected))
    Swag.require(values.head!.prev == null and values.tail!.next == null)
}
