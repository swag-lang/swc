#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

func assertIntArrayPtr(values: &ArrayPtr's32, expected: const [..] s32)->bool
{
    if values.count != @countof(expected) do
        return false

    foreach value, index in values
    {
        if value == null do
            return false
        if dref value != expected[index] do
            return false
    }

    return true
}

#test
{
    var values: ArrayPtr's32
    dref values.addNewPtr() = 1
    dref values.addNewPtr() = 2
    dref values.addNewPtr() = 3

    var copy = values
    @assert(assertIntArrayPtr(&copy, [1, 2, 3]))

    foreach value, index in values
    {
        @assert(copy[index] != value)
        @assert(dref copy[index] == dref value)
    }

    dref copy[1] = 42
    @assert(dref values[1] == 2)
    @assert(dref copy[1] == 42)
}

#test
{
    var values: ArrayPtr's32
    dref values.addNewPtr() = 7
    values.add(cast(*s32) null)
    dref values.addNewPtr() = 9

    var copy = values

    @assert(copy.count == 3)
    @assert(copy[1] == null)
    @assert(copy[0] != null)
    @assert(copy[2] != null)
    @assert(copy[0] != values[0])
    @assert(copy[2] != values[2])
    @assert(dref copy[0] == 7)
    @assert(dref copy[2] == 9)
}
