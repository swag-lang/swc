#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func assertIntSlice(values: const [..] s32, expected: const [..] s32)->bool
{
    if @countof(values) != @countof(expected) do
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
    let backing: [1] s32 = [42]
    let empty = @mkslice(@dataof(backing), 0)

    @assert(Slice.isSorted(empty))
    @assert(Slice.isSorted(empty, func(lhs, rhs: s32)->s32 => rhs <=> lhs))
}

#test
{
    let values: [1] s32 = [7]

    @assert(Slice.isSorted(values))
    @assert(Slice.isSorted(values, func(lhs, rhs: s32)->s32 => rhs <=> lhs))
}

#test
{
    let sorted: [5] s32 = [1, 2, 2, 3, 5]
    let unsorted: [5] s32 = [1, 3, 2, 4, 5]
    let descending: [5] s32 = [9, 7, 4, 4, 1]

    @assert(Slice.isSorted(sorted))
    @assert(!Slice.isSorted(unsorted))
    @assert(Slice.isSorted(descending, func(lhs, rhs: s32)->s32 => rhs <=> lhs))
}

#test
{
    var values: [5] s32 = [5, 1, 4, 2, 3]
    Slice.sort(values)

    let expected: [5] s32 = [1, 2, 3, 4, 5]
    @assert(assertIntSlice(values, expected))
    @assert(Slice.isSorted(values))

    Slice.reverse(values)
    let reversed: [5] s32 = [5, 4, 3, 2, 1]
    @assert(assertIntSlice(values, reversed))
    @assert(Slice.isSorted(values, func(lhs, rhs: s32)->s32 => rhs <=> lhs))
}

#test
{
    var values: [12] s32 = [9, 4, 7, 3, 8, 2, 6, 1, 5, 0, 11, 10]
    Slice.sort(values, true)

    let expected: [12] s32 = [11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
    @assert(assertIntSlice(values, expected))
    @assert(Slice.isSorted(values, func(lhs, rhs: s32)->s32 => rhs <=> lhs))
}
