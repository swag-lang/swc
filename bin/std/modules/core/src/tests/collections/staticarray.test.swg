#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

func assertStaticIntArray(values: const &StaticArray'(s32, 4'u64), expected: const [..] s32)->bool
{
    if values.count != @countof(expected) do
        return false

    for i in values.count
    {
        if values[i] != expected[i] do
            return false
    }

    return true
}

#test
{
    let seed: [4] s32 = [1, 2, 3, 4]

    var values: StaticArray'(s32, 4'u64)
    values = seed

    @assert(values.count == 4)
    @assert(assertStaticIntArray(values, seed))
}

#test
{
    var values: StaticArray'(s32, 4'u64)
    values.resize(4)

    @assert(values.count == 4)
    values[0] = 7
    values[3] = 9
    @assert(values[0] == 7)
    @assert(values[3] == 9)
}
