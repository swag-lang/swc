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

        Swag.require(borrowedDequeEnds(values) == 12)
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

func assertConstDequeBorrow(values: const *Deque's32)->s32
{
    var total = 0
    for &item, index in values[]
    {
        #assert(#typeof(item) == const *s32)
        total += item[] + cast(s32, index)
    }
    return total
}

func assertMutableDequeBorrow(values: *Deque's32)
{
    for &item in values[]
    {
        #assert(#typeof(item) == *s32)
        item[] += 1
        item[] -= 1
    }
}

#test
{
    var values: Deque's32
    values.pushBack(2)
    values.pushFront(1)
    values.pushBack(3)
    values.pushFront(0)

    let expected: [4] s32 = [0, 1, 2, 3]
    Swag.require(assertDeque(values, expected))
    Swag.require(assertConstDequeBorrow(&values) == 12)
    assertMutableDequeBorrow(&values)
    Swag.require(values.front() == 0 and values.back() == 3)
    values[1] = 10
    Swag.require(values[1] == 10)

    Swag.require(values.popFront() == 0)
    Swag.require(values.popBack() == 3)
    Swag.require(values.popFront() == 10)
    Swag.require(values.popBack() == 2)
    Swag.require(values.isEmpty())
}

#test
{
    var values: Deque's32
    for value in 32 do
        values.pushBack(cast(s32, value))
    for value in 16 do
        Swag.require(values.popFront() == cast(s32, value))
    for value in 16 do
        values.pushFront(-cast(s32, value) - 1)

    Swag.require(values.count == 32)
    for value in 16 do
        Swag.require(values.popBack() == 31 - cast(s32, value))
    for value in 16 do
        Swag.require(values.popBack() == -cast(s32, value) - 1)
    Swag.require(values.isEmpty())
}

#test
{
    var values: Deque'String
    values.pushBack("middle")
    values.pushFront("front")
    values.pushBack("back")

    var copy = values
    Swag.require(copy.popFront() == "front")
    Swag.require(copy.popBack() == "back")
    Swag.require(values.count == 3 and copy.count == 1)

    values.clear()
    Swag.require(values.isEmpty() and values.capacity() > 0)
    values.free()
    Swag.require(values.capacity() == 0)
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
                values.pushFront(cast(s32, value))
            else do
                values.pushBack(cast(s32, value))
        }

        let first    = &values[0]
        let last     = &values[values.count - 1]
        let capacity = values.capacity()
        Swag.require(values.frontPtr() == first)
        Swag.require(values.backPtr() == last)
        Swag.require(values.capacity() == capacity)
        values.frontPtr()[] = 10
        values.backPtr()[]  = 20
        Swag.require(values.popFront() == 10)
        Swag.require(values.popBack() == 20)
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
            Swag.require(values.count == 1 and values.capacity() >= capacity)
            Swag.require(values.front() == 42 and values.back() == 42)
        }
    }
}

// Growing combined capacity preserves the queue's logical order across both segments.
#test
{
    var values: Deque's32
    values.pushFront(1)
    values.pushBack(2)
    values.pushFront(0)

    let expected: [3] s32 = [0, 1, 2]
    let requested         = values.capacity() + 7
    values.reserve(requested)

    Swag.require(values.capacity() >= requested)
    Swag.require(assertDeque(values, expected))
}
