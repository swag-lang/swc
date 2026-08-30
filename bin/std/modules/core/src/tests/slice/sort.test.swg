#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertIntSlice(values: const [..] s32, expected: const [..] s32)->bool
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
    let backing: [1] s32 = [42]
    let empty            = Swag.makeSlice(backing.buffer, 0)

    Swag.assert(Slice.isSorted(empty))
    Swag.assert(Slice.isSorted(empty, func(lhs, rhs: s32)->s32 => rhs <=> lhs))
}

#test
{
    let values: [1] s32 = [7]

    Swag.assert(Slice.isSorted(values))
    Swag.assert(Slice.isSorted(values, func(lhs, rhs: s32)->s32 => rhs <=> lhs))
}

#test
{
    let sorted:     [5] s32 = [1, 2, 2, 3, 5]
    let unsorted:   [5] s32 = [1, 3, 2, 4, 5]
    let descending: [5] s32 = [9, 7, 4, 4, 1]

    Swag.assert(Slice.isSorted(sorted))
    Swag.assert(!Slice.isSorted(unsorted))
    Swag.assert(Slice.isSorted(descending, func(lhs, rhs: s32)->s32 => rhs <=> lhs))
}

#test
{
    var values: [5] s32 = [5, 1, 4, 2, 3]
    Slice.sort(values)

    let expected: [5] s32 = [1, 2, 3, 4, 5]
    Swag.assert(assertIntSlice(values, expected))
    Swag.assert(Slice.isSorted(values))

    Slice.reverse(values)
    let reversed: [5] s32 = [5, 4, 3, 2, 1]
    Swag.assert(assertIntSlice(values, reversed))
    Swag.assert(Slice.isSorted(values, func(lhs, rhs: s32)->s32 => rhs <=> lhs))
}

#test
{
    var values: [12] s32 = [9, 4, 7, 3, 8, 2, 6, 1, 5, 0, 11, 10]
    Slice.sort(values, true)

    let expected: [12] s32 = [11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
    Swag.assert(assertIntSlice(values, expected))
    Swag.assert(Slice.isSorted(values, func(lhs, rhs: s32)->s32 => rhs <=> lhs))
}

// Number of comparisons Slice.sort needs for 'values', which the sort must leave ordered.
func countedSortCompares(values: [..] s32)->u64
{
    var compares = 0'u64
    Slice.sort(values, func|counter = &compares|(x, y: s32)->s32
    {
        counter[] += 1
        return x <=> y
    })

    Swag.assert(Slice.isSorted(values))
    return compares
}

// An input that is already ordered, or exactly reversed, must not cost the quadratic case.
// Both are what a caller produces by re-sorting a list it sorted a moment ago.
#test
{
    const Count       = 2000'u64
    const MaxCompares = 20 * Count

    var ascending: Core.Array's32
    var reversed:  Core.Array's32
    var equal:     Core.Array's32
    for i in Count
    {
        ascending.add(cast(s32) i)
        reversed.add(cast(s32) (Count - i))
        equal.add(7)
    }

    Swag.assert(countedSortCompares(ascending.toSlice()) < MaxCompares)
    Swag.assert(countedSortCompares(reversed.toSlice()) < MaxCompares)
    Swag.assert(countedSortCompares(equal.toSlice()) < MaxCompares)
}
