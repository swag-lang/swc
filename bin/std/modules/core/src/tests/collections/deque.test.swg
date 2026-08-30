#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

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
