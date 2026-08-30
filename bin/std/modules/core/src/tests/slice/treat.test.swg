#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func sameValues(values: const [..] s32, expected: const [..] s32)->bool
{
    return Slice.equals(values, expected)
}

#test
{
    var values: [4] s32 = [1, 2, 3, 4]
    let bias            = 10

    Slice.forEachMutable(values, func|bias|(it: *s32) { it[] += bias })
    Swag.assert(sameValues(values, [11, 12, 13, 14]))

    let mapped = Slice.map(values, func(value: s32)->s32 { return value / 2 })
    Swag.assert(mapped.count == 4)
    Swag.assert(sameValues(cast([..] s32) mapped, [5, 6, 6, 7]))
}

#test
{
    Swag.assert(Slice.reduce([5], func(left, right: s32)->s32 { return left + right }) == 5)
    Swag.assert(Slice.reduce([1, 2, 3, 4], func(left, right: s32)->s32 { return left + right }) == 10)
    Swag.assert(Slice.reduce([2, 3, 4], func(left, right: s32)->s32 { return left * right }) == 24)
}

#test
{
    let values: [5] s32 = [4, -3, 9, -1, 9]
    let minValue        = Slice.min(values)
    let maxValue        = Slice.max(values)

    Swag.assert(minValue.value == -3)
    Swag.assert(minValue.index == 1)
    Swag.assert(maxValue.value == 9)
    Swag.assert(maxValue.index == 2)

    let singleMin = Slice.min([42])
    let singleMax = Slice.max([42])
    Swag.assert(singleMin.value == 42 and singleMin.index == 0)
    Swag.assert(singleMax.value == 42 and singleMax.index == 0)
}

#test
{
    let values: [4] s32 = [2, 4, 6, 8]
    let empty           = Swag.makeSlice(values.buffer, 0)

    Swag.assert(Slice.allOf(values, func(value: s32)->bool { return value % 2 == 0 }))
    Swag.assert(!Slice.allOf(values, func(value: s32)->bool { return value < 8 }))

    Swag.assert(Slice.anyOf(values, func(value: s32)->bool { return value == 6 }))
    Swag.assert(!Slice.anyOf(values, func(value: s32)->bool { return value == 5 }))

    Swag.assert(Slice.noneOf(values, func(value: s32)->bool { return value < 0 }))
    Swag.assert(!Slice.noneOf(values, func(value: s32)->bool { return value == 4 }))

    Swag.assert(Slice.allOf(empty, func(value: s32)->bool { return false }))
    Swag.assert(!Slice.anyOf(empty, func(value: s32)->bool { return true }))
    Swag.assert(Slice.noneOf(empty, func(value: s32)->bool { return true }))
}

#test
{
    var odd:    [5] s32 = [1, 2, 3, 4, 5]
    var single: [1] s32 = [9]

    Slice.reverse(odd)
    Slice.reverse(single)

    Swag.assert(sameValues(odd, [5, 4, 3, 2, 1]))
    Swag.assert(sameValues(single, [9]))
}

#test
{
    var values: [3] s32 = [1, 2, 3]

    Swag.assert(Slice.nextPermutation(values))
    Swag.assert(sameValues(values, [1, 3, 2]))
    Swag.assert(Slice.nextPermutation(values))
    Swag.assert(sameValues(values, [2, 1, 3]))
    Swag.assert(Slice.nextPermutation(values))
    Swag.assert(sameValues(values, [2, 3, 1]))
    Swag.assert(Slice.nextPermutation(values))
    Swag.assert(sameValues(values, [3, 1, 2]))
    Swag.assert(Slice.nextPermutation(values))
    Swag.assert(sameValues(values, [3, 2, 1]))
    Swag.assert(!Slice.nextPermutation(values))
    Swag.assert(sameValues(values, [3, 2, 1]))
}
