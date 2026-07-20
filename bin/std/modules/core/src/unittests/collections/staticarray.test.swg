#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

var StaticArrayDropCount: s32 = 0

struct StaticArrayVisitProbe
{
    value: s32
}

struct StaticArrayDropTracked
{
    value: s32
}

impl StaticArrayDropTracked
{
    mtd opDrop()
    {
        if .value == 0 do
            return

        @assert(.value > 0)
        StaticArrayDropCount += 1
        .value = -1
    }
}

func resetStaticArrayDropTrace()
{
    StaticArrayDropCount = 0
}

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

func visitStructStaticArray(values: &StaticArray'(StaticArrayVisitProbe, 4'u64))->s32
{
    for value, index in values where value.value != 12
    {
        if index == 0 do
            continue

        return value.value + cast(s32) index
    }

    return 0
}

func visitStructStaticArrayReverse(values: &StaticArray'(StaticArrayVisitProbe, 4'u64))->s32
{
    var score = 0
    for #reverse value, index in values
    {
        score += value.value + cast(s32) index
        if value.value == 12 do
            return score
    }

    return score
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

#test
{
    var values: StaticArray'(s32, 4'u64)
    values.add(1)
    values.add(2)

    var moved: s32 = 3
    values.insertAt(values.count, #move moved)

    let expected: [3] s32 = [1, 2, 3]
    @assert(assertStaticIntArray(values, expected))
}

#test
{
    var values: StaticArray'(StaticArrayVisitProbe, 4'u64)
    values.add(StaticArrayVisitProbe{value: 1})
    values.add(StaticArrayVisitProbe{value: 2})
    values.add(StaticArrayVisitProbe{value: 3})

    for &value in values do
        value.value += 10

    @assert(values[0].value == 11)
    @assert(values[1].value == 12)
    @assert(values[2].value == 13)
    @assert(visitStructStaticArray(&values) == 15)
    @assert(visitStructStaticArrayReverse(&values) == 28)
}

#test
{
    let seed: [4] s32 = [10, 20, 30, 40]

    var values: StaticArray'(s32, 4'u64)
    values = seed

    var reverseIndex = Swag.U64.Max
    for #reverse value, index in values
    {
        if value == 30 do
            reverseIndex = index
    }

    @assert(reverseIndex == 2)
}

#test
{
    resetStaticArrayDropTrace()

    {
        var values: StaticArray'(StaticArrayDropTracked, 4'u64)
        let seed = values.emplaceAddress(4)
        seed[0].value = 1
        seed[1].value = 2
        seed[2].value = 3
        seed[3].value = 4

        values.removeAtOrdered(2, 2)

        @assert(values.count == 2)
        @assert(values[0].value == 1)
        @assert(values[1].value == 2)
    }

    @assert(StaticArrayDropCount == 4)
}
