#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertDeque(values: &Deque's32, expected: const [..] s32)->bool
{
    if values.count != @countof(expected) do
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
    @assert(assertDeque(&values, expected))
    @assert(values.front() == 0 and values.back() == 3)
    values[1] = 10
    @assert(values[1] == 10)

    @assert(values.popFront() == 0)
    @assert(values.popBack() == 3)
    @assert(values.popFront() == 10)
    @assert(values.popBack() == 2)
    @assert(values.isEmpty())
}

#test
{
    var values: Deque's32
    for value in 32 do
        values.pushBack(cast(s32) value)
    for value in 16 do
        @assert(values.popFront() == cast(s32) value)
    for value in 16 do
        values.pushFront(-cast(s32) value - 1)

    @assert(values.count == 32)
    for value in 16 do
        @assert(values.popBack() == 31 - cast(s32) value)
    for value in 16 do
        @assert(values.popBack() == -cast(s32) value - 1)
    @assert(values.isEmpty())
}

#test
{
    var values: Deque'String
    values.pushBack("middle")
    values.pushFront("front")
    values.pushBack("back")

    var copy = values
    @assert(copy.popFront() == "front")
    @assert(copy.popBack() == "back")
    @assert(values.count == 3 and copy.count == 1)

    values.clear()
    @assert(values.isEmpty() and values.capacity() > 0)
    values.free()
    @assert(values.capacity() == 0)
}
