#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    var empty: [..] s32 = null
    let values: [6] s32 = [1, 3, 5, 7, 9, 11]

    @assert(Slice.findSorted(empty, 1) == Swag.U64.Max)
    @assert(Slice.findSorted(values, 1) == 0)
    @assert(Slice.findSorted(values, 7) == 3)
    @assert(Slice.findSorted(values, 11) == 5)
    @assert(Slice.findSorted(values, 4) == Swag.U64.Max)
    @assert(Slice.containsSorted(values, 9))
    @assert(!Slice.containsSorted(values, 8))
}

#test
{
    let values: [4] string = ["alpha", "beta", "gamma", "beta"]

    @assert(Slice.findLinear(values, "alpha") == 0)
    @assert(Slice.findLinear(values, "beta") == 1)
    @assert(Slice.findLinear(values, "missing") == Swag.U64.Max)

    @assert(Slice.contains(values, "gamma"))
    @assert(!Slice.contains(values, "delta"))
}

#test
{
    let values: [7] s32 = [1, 2, 3, 4, 5, 6, 7]

    @assert(Slice.findSlice(values, [1, 2]) == 0)
    @assert(Slice.findSlice(values, [3, 4, 5]) == 2)
    @assert(Slice.findSlice(values, [6, 7]) == 5)
    @assert(Slice.findSlice(values, [7, 8]) == Swag.U32.Max)
    @assert(Slice.findSlice(values, values) == 0)
}

#test
{
    var emptyA: [..] s32 = null
    var emptyB: [..] s32 = null
    let left: [4] s32 = [1, 2, 3, 4]
    let same: [4] s32 = [1, 2, 3, 4]
    let other: [4] s32 = [1, 2, 4, 3]

    @assert(Slice.equals(emptyA, emptyB))
    @assert(Slice.equals(left, same))
    @assert(!Slice.equals(left, other))
    @assert(!Slice.equals(left, [1, 2, 3]))
}
