#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#[Swag.NoCopy]
struct DequeBorrowedItem
{
    value: s32
}

func borrowedDequeEnds(values: Deque'DequeBorrowedItem)->s32
{
    let first = values.frontPtr()
    let last  = values.backPtr()
    #assert(#typeof(first) == const *DequeBorrowedItem)
    #assert(#typeof(last) == const *DequeBorrowedItem)
    return first.value * 10 + last.value
}

#test
{
    for frontOnly in [false, true]
    {
        var values: Deque'DequeBorrowedItem
        var first = DequeBorrowedItem{value: 1}
        var last  = DequeBorrowedItem{value: 2}
        if frontOnly
        {
            values.pushFront(#move last)
            values.pushFront(#move first)
        }
        else
        {
            values.pushBack(#move first)
            values.pushBack(#move last)
        }

        Swag.assert(borrowedDequeEnds(values) == 12)
    }
}

func assertDeque(values: Deque's32, expected: const [..] s32)->bool
{
    if values.count != expected.count do
        return false
    for value, index in values
    {
        if value != expected[index] do
            return false
    }

    return true
}

#test
{
    var values: Deque's32
    values.pushBack(2)
    values.pushFront(1)
    values.pushBack(3)
    values.pushFront(0)

    let expected: [4] s32 = [0, 1, 2, 3]
    Swag.assert(assertDeque(values, expected))
    Swag.assert(values.front() == 0 and values.back() == 3)
    values[1] = 10
    Swag.assert(values[1] == 10)

    Swag.assert(values.popFront() == 0)
    Swag.assert(values.popBack() == 3)
    Swag.assert(values.popFront() == 10)
    Swag.assert(values.popBack() == 2)
    Swag.assert(values.isEmpty())
}

#test
{
    var values: Deque's32
    for value in 32 do
        values.pushBack(cast(s32) value)
    for value in 16 do
        Swag.assert(values.popFront() == cast(s32) value)
    for value in 16 do
        values.pushFront(-cast(s32) value - 1)

    Swag.assert(values.count == 32)
    for value in 16 do
        Swag.assert(values.popBack() == 31 - cast(s32) value)
    for value in 16 do
        Swag.assert(values.popBack() == -cast(s32) value - 1)
    Swag.assert(values.isEmpty())
}

#test
{
    var values: Deque'String
    values.pushBack("middle")
    values.pushFront("front")
    values.pushBack("back")

    var copy = values
    Swag.assert(copy.popFront() == "front")
    Swag.assert(copy.popBack() == "back")
    Swag.assert(values.count == 3 and copy.count == 1)

    values.clear()
    Swag.assert(values.isEmpty() and values.capacity() > 0)
    values.free()
    Swag.assert(values.capacity() == 0)
}

// Borrowing either end must keep every element in its existing storage.
#test
{
    for frontOnly in [false, true]
    {
        var values: Deque's32
        for value in 5
        {
            if frontOnly do
                values.pushFront(cast(s32) value)
            else do
                values.pushBack(cast(s32) value)
        }

        let first    = &values[0]
        let last     = &values[values.count - 1]
        let capacity = values.capacity()
        Swag.assert(values.frontPtr() == first)
        Swag.assert(values.backPtr() == last)
        Swag.assert(values.capacity() == capacity)
        values.frontPtr()[] = 10
        values.backPtr()[]  = 20
        Swag.assert(values.popFront() == 10)
        Swag.assert(values.popBack() == 20)
    }
}

// Reserving less storage preserves the elements and their existing capacity.
#test
{
    for frontOnly in [false, true]
    {
        var values: Deque's32
        if frontOnly do
            values.pushFront(42)
        else do
            values.pushBack(42)
        let capacity = values.capacity()
        for requested in [0'u64, 1'u64, capacity]
        {
            values.reserve(requested)
            Swag.assert(values.count == 1 and values.capacity() >= capacity)
            Swag.assert(values.front() == 42 and values.back() == 42)
        }
    }
}
