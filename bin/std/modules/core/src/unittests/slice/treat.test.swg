#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func sameValues(values: const [..] s32, expected: const [..] s32)->bool
{
    return Slice.equals(values, expected)
}

#test
{
    var values: [4] s32 = [1, 2, 3, 4]
    let bias = 10

    Slice.modify(values, func|bias|(it: #nonull *s32)
    {
        dref it += bias
    })
    @assert(sameValues(values, [11, 12, 13, 14]))

    let mapped = Slice.map(values, func(value: s32)->s32
    {
        return value / 2
    })
    @assert(mapped.count == 4)
    @assert(sameValues(cast([..] s32) mapped, [5, 6, 6, 7]))
}

#test
{
    @assert(Slice.reduce([5], func(left, right: s32)->s32 { return left + right }) == 5)
    @assert(Slice.reduce([1, 2, 3, 4], func(left, right: s32)->s32 { return left + right }) == 10)
    @assert(Slice.reduce([2, 3, 4], func(left, right: s32)->s32 { return left * right }) == 24)
}

#test
{
    let values: [5] s32 = [4, -3, 9, -1, 9]
    let minValue = Slice.min(values)
    let maxValue = Slice.max(values)

    @assert(minValue.value == -3)
    @assert(minValue.index == 1)
    @assert(maxValue.value == 9)
    @assert(maxValue.index == 2)

    let singleMin = Slice.min([42])
    let singleMax = Slice.max([42])
    @assert(singleMin.value == 42 and singleMin.index == 0)
    @assert(singleMax.value == 42 and singleMax.index == 0)
}

#test
{
    let values: [4] s32 = [2, 4, 6, 8]
    var empty: [..] s32 = null

    @assert(Slice.allOf(values, func(value: s32)->bool { return value % 2 == 0 }))
    @assert(!Slice.allOf(values, func(value: s32)->bool { return value < 8 }))

    @assert(Slice.anyOf(values, func(value: s32)->bool { return value == 6 }))
    @assert(!Slice.anyOf(values, func(value: s32)->bool { return value == 5 }))

    @assert(Slice.noneOf(values, func(value: s32)->bool { return value < 0 }))
    @assert(!Slice.noneOf(values, func(value: s32)->bool { return value == 4 }))

    @assert(Slice.allOf(empty, func(value: s32)->bool { return false }))
    @assert(!Slice.anyOf(empty, func(value: s32)->bool { return true }))
    @assert(Slice.noneOf(empty, func(value: s32)->bool { return true }))
}

#test
{
    var odd: [5] s32 = [1, 2, 3, 4, 5]
    var single: [1] s32 = [9]

    Slice.reverse(odd)
    Slice.reverse(single)

    @assert(sameValues(odd, [5, 4, 3, 2, 1]))
    @assert(sameValues(single, [9]))
}

#test
{
    var values: [3] s32 = [1, 2, 3]

    @assert(Slice.nextPermutation(values))
    @assert(sameValues(values, [1, 3, 2]))
    @assert(Slice.nextPermutation(values))
    @assert(sameValues(values, [2, 1, 3]))
    @assert(Slice.nextPermutation(values))
    @assert(sameValues(values, [2, 3, 1]))
    @assert(Slice.nextPermutation(values))
    @assert(sameValues(values, [3, 1, 2]))
    @assert(Slice.nextPermutation(values))
    @assert(sameValues(values, [3, 2, 1]))
    @assert(!Slice.nextPermutation(values))
    @assert(sameValues(values, [3, 2, 1]))
}
