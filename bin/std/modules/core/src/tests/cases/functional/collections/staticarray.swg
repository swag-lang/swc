#global if #command == Swag.CompilerCommand.Test
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

        Swag.require(.value > 0)
        StaticArrayDropCount += 1
        .value = -1
    }
}

func resetStaticArrayDropTrace()
{
    StaticArrayDropCount = 0
}

func visitStructStaticArray(values: *StaticArray'(StaticArrayVisitProbe, 4'u64))->s32
{
    for value, index in values[] where value.value != 12
    {
        if index == 0 do
            continue

        return value.value + cast(s32, index)
    }

    return 0
}

func visitStructStaticArrayReverse(values: *StaticArray'(StaticArrayVisitProbe, 4'u64))->s32
{
    var score = 0
    for value, index in values.reversed()
    {
        score += value.value + cast(s32, index)
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

    Swag.require(values.count == 4)
    Swag.require(Slice.equals(values.toSlice(), seed))
}

#test
{
    var values: StaticArray'(s32, 4'u64)
    values.resize(4)

    Swag.require(values.count == 4)
    values[0] = 7
    values[3] = 9
    Swag.require(values[0] == 7)
    Swag.require(values[3] == 9)
}

#test
{
    var values: StaticArray'(s32, 3'u64)
    values.addOnce(1)
    values.addOnce(2)
    values.addOnce(2)

    Swag.require(values.count == 2)
    Swag.require(values[0] == 1 and values[1] == 2)

    values.addOnce(3)
    values.addOnce(1)
    Swag.require(values.count == 3)
    Swag.require(values[0] == 1 and values[1] == 2 and values[2] == 3)

    let fullArray = Swag.catchPanic(func|&values|() { values.addOnce(4) })
    Swag.require(fullArray.raised)
    Swag.require(values.count == 3)
    Swag.require(values[0] == 1 and values[1] == 2 and values[2] == 3)
}

#test
{
    var values: StaticArray'(s32, 4'u64)
    values.add(1)
    values.add(2)

    var moved: s32 = 3
    values.insertAt(values.count, #move moved)

    let expected: [3] s32 = [1, 2, 3]
    Swag.require(Slice.equals(values.toSlice(), expected))
}

#test
{
    var values: StaticArray'(StaticArrayVisitProbe, 4'u64)
    values.add({value: 1})
    values.add({value: 2})
    values.add({value: 3})

    for &value in values do
        value.value += 10

    Swag.require(values[0].value == 11)
    Swag.require(values[1].value == 12)
    Swag.require(values[2].value == 13)
    Swag.require(visitStructStaticArray(&values) == 15)
    Swag.require(visitStructStaticArrayReverse(&values) == 28)
}

#test
{
    let seed: [4] s32 = [10, 20, 30, 40]

    var values: StaticArray'(s32, 4'u64)
    values = seed

    var reverseIndex = Swag.U64.Max
    for value, index in values.reversed()
    {
        if value == 30 do
            reverseIndex = index
    }

    Swag.require(reverseIndex == 2)
}

#test
{
    resetStaticArrayDropTrace()

    scope
    {
        var values: StaticArray'(StaticArrayDropTracked, 4'u64)
        let seed = values.emplaceAddress(4)
        seed[0].value = 1
        seed[1].value = 2
        seed[2].value = 3
        seed[3].value = 4

        values.removeAtOrdered(2, 2)

        Swag.require(values.count == 2)
        Swag.require(values[0].value == 1)
        Swag.require(values[1].value == 2)
    }

    Swag.require(StaticArrayDropCount == 4)
}

// An element can be inserted back into its own array: the shift would otherwise overwrite it
// before it is copied.
#test
{
    var s: StaticArray'(String, 8)
    s.add("one")
    s.add("two")
    s.add("three")
    s.insertBorrowedAt(0, &s[2])
    Swag.require(s.count == 4 and s[0] == "three" and s[1] == "one" and s[2] == "two" and s[3] == "three")
    s.insertBorrowedAt(1, &s[3])
    Swag.require(s.count == 5 and s[1] == "three" and s[2] == "one" and s[4] == "three")
}
