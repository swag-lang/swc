#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

var ArrayDropCount: s32 = 0
var ArrayDropTrace: s64 = 0
var ArrayDropMask: u32 = 0

struct ArrayDropTracked
{
    value: s32
}

struct ArrayVisitProbe
{
    value: s32
}

impl ArrayDropTracked
{
    mtd opDrop()
    {
        if .value == 0 do
            return

        let bit = 1'u32 << cast(u32) .value
        if !(ArrayDropMask & bit)
        {
            ArrayDropCount += 1
            ArrayDropTrace = ArrayDropTrace * 100 + cast(s64) .value
            ArrayDropMask |= bit
        }

        .value = 0
    }
}

func resetArrayDropTrace()
{
    ArrayDropCount = 0
    ArrayDropTrace = 0
    ArrayDropMask = 0
}

func assertIntArray(values: const &Array's32, expected: const [..] s32)->bool
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

func assertStringArray(values: const &Array'String, expected: const [..] string)->bool
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

func assertStringSlice(values: const [..] String, expected: const [..] string)->bool
{
    if @countof(values) != @countof(expected) do
        return false

    for i in @countof(values)
    {
        if values[i] != expected[i] do
            return false
    }

    return true
}

func assertStaticStringArray(values: const &StaticArray'(String, 4'u64), expected: const [..] string)->bool
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

func visitStructArray(values: &Array'ArrayVisitProbe)->s32
{
    for value, index in values where value.value != 12
    {
        if index == 0 do
            continue

        return value.value + cast(s32) index
    }

    return 0
}

func visitStructArrayReverse(values: &Array'ArrayVisitProbe)->s32
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
    var values: Array's32
    @assert(values.isEmpty())

    values.reserve(2)
    @assert(values.capacity >= 2)

    values.add(10)
    values.add(20)
    values.addOnce(20)
    values.addOnce(30)

    let extra = values.emplaceAddress()
    extra[0] = 40

    let tail = values.emplaceInitAddress(2)
    @assert(tail[0] == 0)
    @assert(tail[1] == 0)
    tail[0] = 50
    tail[1] = 60

    let expectedFilled: [6] s32 = [10, 20, 30, 40, 50, 60]
    @assert(assertIntArray(values, expectedFilled))
    @assert(values.contains(20))
    @assert(!values.contains(99))
    @assert(values.front() == 10)
    @assert(values.back() == 60)

    @assert(values.popBack() == 60)
    values.removeBack()
    let expectedAfterPop: [4] s32 = [10, 20, 30, 40]
    @assert(assertIntArray(values, expectedAfterPop))

    values.clear()
    @assert(values.isEmpty())
    @assert(values.count == 0)
}

#test
{
    var values: Array's32
    let seed: [4] s32 = [4, 1, 3, 2]
    values.add(seed)

    let asSlice = cast([..] s32) values
    @assert(@countof(asSlice) == 4)
    @assert(asSlice[0] == 4)
    @assert(asSlice[3] == 2)

    let first = values.ref1(0)
    first = 9

    let bottomRight = values.ref2(1, 1, 2)
    bottomRight = 7

    let expectedGrid: [4] s32 = [9, 1, 3, 7]
    @assert(assertIntArray(values, expectedGrid))

    var weightedSum: s32 = 0
    for value, ordinal in values
    {
        weightedSum += value * cast(s32) (ordinal + 1)
    }

    @assert(weightedSum == 48)

    for &value, ordinal in values
    {
        dref value -= cast(s32) ordinal
    }

    let expectedVisited: [4] s32 = [9, 0, 1, 4]
    @assert(assertIntArray(values, expectedVisited))

    let middle = values[1 to 2]
    @assert(@countof(middle) == 2)
    @assert(middle[0] == 0)
    @assert(middle[1] == 1)

    values.sort()
    let expectedSorted: [4] s32 = [0, 1, 4, 9]
    @assert(assertIntArray(values, expectedSorted))

    values.sortReverse()
    let expectedReverse: [4] s32 = [9, 4, 1, 0]
    @assert(assertIntArray(values, expectedReverse))
}

#test
{
    var values: Array's32
    let seed: [3] s32 = [1, 2, 3]
    let inserted: [2] s32 = [7, 8]
    values.add(seed)

    values.insertAt(0, 0)
    values.insertAt(2, inserted)
    values.insertAt(values.count, 9)

    let expectedInserted: [7] s32 = [0, 1, 7, 8, 2, 3, 9]
    @assert(assertIntArray(values, expectedInserted))

    values.removeAtOrdered(2, 2)
    let expectedOrderedRemove: [5] s32 = [0, 1, 2, 3, 9]
    @assert(assertIntArray(values, expectedOrderedRemove))

    values.removeAt(1)
    let expectedUnorderedRemove: [4] s32 = [0, 9, 2, 3]
    @assert(assertIntArray(values, expectedUnorderedRemove))

    values.removeOrdered(2)
    let expectedRemoveOrderedValue: [3] s32 = [0, 9, 3]
    @assert(assertIntArray(values, expectedRemoveOrderedValue))

    values.remove(9)
    let expectedRemoveValue: [2] s32 = [0, 3]
    @assert(assertIntArray(values, expectedRemoveValue))

    values.swap(0, 1)
    let expectedSwap: [2] s32 = [3, 0]
    @assert(assertIntArray(values, expectedSwap))
}

#test
{
    var values: Array's32
    let seed: [6] s32 = [0, 1, 2, 3, 4, 5]
    values.add(seed)

    values.remove(2, 2)

    let expected: [4] s32 = [0, 1, 4, 5]
    @assert(assertIntArray(values, expected))
}

#test
{
    var values: Array's32
    @assert(@countof(values) == 0)
    @assert(@dataof(values) == null)

    let seed: [4] s32 = [5, 1, 9, 3]
    values.add(seed)

    @assert(@countof(values) == 4)
    let raw = cast(const [*] s32) @dataof(values)
    @assert(raw != null)
    @assert(raw[0] == 5)
    @assert(raw[3] == 3)

    values[1] = 7
    values[1] += 2
    values[2] -= 4
    let expectedAssigned: [4] s32 = [5, 9, 5, 3]
    @assert(assertIntArray(values, expectedAssigned))

    var none: [..] s32 = null
    values.add(none)
    @assert(assertIntArray(values, expectedAssigned))

    var movedFront: s32 = 4
    var movedBack: s32 = 8
    values.insertAt(0, #move movedFront)
    values.add(#move movedBack)

    let expectedMoved: [6] s32 = [4, 5, 9, 5, 3, 8]
    @assert(assertIntArray(values, expectedMoved))

    values.sort(func||(a, b)
    {
        return b <=> a
    })

    let expectedSortedByCallback: [6] s32 = [9, 8, 5, 5, 4, 3]
    @assert(assertIntArray(values, expectedSortedByCallback))
}

#test
{
    let seed: [3] s32 = [1, 2, 3]

    var values: Array's32
    values = seed
    @assert(assertIntArray(values, seed))

    var copy: Array's32 = values
    let frontPtr = copy.frontPtr()
    let backPtr = copy.backPtr()
    dref frontPtr = 9
    dref backPtr = 7

    let expectedOriginal: [3] s32 = [1, 2, 3]
    let expectedCopy: [3] s32 = [9, 2, 7]
    @assert(assertIntArray(values, expectedOriginal))
    @assert(assertIntArray(copy, expectedCopy))

    copy.fill(4)
    let expectedFilled: [3] s32 = [4, 4, 4]
    @assert(assertIntArray(copy, expectedFilled))

    copy.resize(1)
    let expectedShrunk: [1] s32 = [4]
    @assert(assertIntArray(copy, expectedShrunk))

    copy.growResize(4)
    let expectedRegrown: [4] s32 = [4, 0, 0, 0]
    @assert(assertIntArray(copy, expectedRegrown))
}

#test
{
    var values: Array'ArrayVisitProbe
    values.add(ArrayVisitProbe{value: 1})
    values.add(ArrayVisitProbe{value: 2})
    values.add(ArrayVisitProbe{value: 3})

    for value in values do
        value.value += 10

    @assert(values[0].value == 11)
    @assert(values[1].value == 12)
    @assert(values[2].value == 13)
    @assert(visitStructArrayReverse(&values) == 28)
}

#test
{
    var values: Array's32

    let seed: [3] s32 = [1, 4, 5]
    let inserted: [2] s32 = [2, 3]
    values.add(seed)
    values.emplaceAt(1, inserted)

    let expectedEmplaced: [5] s32 = [1, 2, 3, 4, 5]
    @assert(assertIntArray(values, expectedEmplaced))

    values.growResize(7)
    @assert(values[5] == 0)
    @assert(values[6] == 0)

    values.reserve(14)
    let snapshot = values.toSlice()
    values.add(snapshot)

    let expectedSelfAppend: [14] s32 = [1, 2, 3, 4, 5, 0, 0, 1, 2, 3, 4, 5, 0, 0]
    @assert(assertIntArray(values, expectedSelfAppend))
}

#test
{
    var values: Array's32
    let seed: [4] s32 = [10, 20, 30, 40]
    values.add(seed)

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
    var values: Array'String
    values.add(String.from("11111111111111111111111111111111"))
    values.add(String.from("22222222222222222222222222222222"))
    values.add(String.from("33333333333333333333333333333333"))
    values.add(String.from("44444444444444444444444444444444"))

    let tail = values[1 to 3]
    values.opSet(tail)

    let expected: [3] string =
        ["22222222222222222222222222222222", "33333333333333333333333333333333", "44444444444444444444444444444444"]
    @assert(assertStringArray(values, expected))
}

#test
{
    var values: StaticArray'(String, 4'u64)
    values.add(String.from("11111111111111111111111111111111"))

    let expected: [1] string =
        ["11111111111111111111111111111111"]
    @assert(assertStaticStringArray(values, expected))
}

#test
{
    var values: StaticArray'(String, 4'u64)
    values.add(String.from("11111111111111111111111111111111"))
    values.add(String.from("22222222222222222222222222222222"))
    values.add(String.from("33333333333333333333333333333333"))
    values.add(String.from("44444444444444444444444444444444"))

    let tail = values[1 to 3]
    values.opSet(tail)

    let expected: [3] string =
        ["22222222222222222222222222222222", "33333333333333333333333333333333", "44444444444444444444444444444444"]
    @assert(assertStaticStringArray(values, expected))
}

#test
{
    var values: Array'String
    values.reserve(8)
    values.add(String.from("11111111111111111111111111111111"))
    values.add(String.from("22222222222222222222222222222222"))
    values.add(String.from("33333333333333333333333333333333"))
    values.add(String.from("44444444444444444444444444444444"))

    let middle = values[1 to 2]
    values.insertAt(0, middle)

    let expected: [6] string =
        ["22222222222222222222222222222222", "33333333333333333333333333333333", "11111111111111111111111111111111",
         "22222222222222222222222222222222", "33333333333333333333333333333333", "44444444444444444444444444444444"]
    @assert(assertStringSlice(values.toSlice(), expected))
}

#test
{
    var values: StaticArray'(String, 8'u64)
    values.add(String.from("11111111111111111111111111111111"))
    values.add(String.from("22222222222222222222222222222222"))
    values.add(String.from("33333333333333333333333333333333"))
    values.add(String.from("44444444444444444444444444444444"))

    let tail = values[1 to 2]
    values.add(tail)

    let expected: [6] string =
        ["11111111111111111111111111111111", "22222222222222222222222222222222", "33333333333333333333333333333333",
         "44444444444444444444444444444444", "22222222222222222222222222222222", "33333333333333333333333333333333"]
    @assert(assertStringSlice(values.toSlice(), expected))
}

#test
{
    var values: StaticArray'(String, 8'u64)
    values.add(String.from("11111111111111111111111111111111"))
    values.add(String.from("22222222222222222222222222222222"))
    values.add(String.from("33333333333333333333333333333333"))
    values.add(String.from("44444444444444444444444444444444"))

    let middle = values[1 to 2]
    values.insertAt(0, middle)

    let expected: [6] string =
        ["22222222222222222222222222222222", "33333333333333333333333333333333", "11111111111111111111111111111111",
         "22222222222222222222222222222222", "33333333333333333333333333333333", "44444444444444444444444444444444"]
    @assert(assertStringSlice(values.toSlice(), expected))
}

#test
{
    var values = Array'u8.createBuffer(6)
    @assert(values.count == 6)
    @assert(values.capacity >= 6)

    for i in values.count do
        @assert(values[i] == 0)

    values.fill(7)
    let frontPtr = values.frontPtr()
    let backPtr = values.backPtr()
    dref frontPtr = 1
    dref backPtr = 9

    @assert(values.front() == 1)
    @assert(values.back() == 9)

    values.reserve(0)
    @assert(values.isEmpty())
    @assert(values.count == 0)
    @assert(values.capacity == 0)

    values.add(5)
    @assert(values.count == 1)
    @assert(values[0] == 5)
}

#test
{
    resetArrayDropTrace()

    {
        var values: StaticArray'(ArrayDropTracked, 5'u64)
        let seed = values.emplaceAddress(5)
        seed[0].value = 1
        seed[1].value = 2
        seed[2].value = 3
        seed[3].value = 4
        seed[4].value = 5

        values.remove(1, 3)

        @assert(values.count == 2)
        @assert(values[0].value == 1)
        @assert(values[1].value == 5)
    }
    @assert(ArrayDropCount == 5)
}

#test
{
    resetArrayDropTrace()

    {
        var values: Array'ArrayDropTracked
        let seed = values.emplaceAddress(5)
        seed[0].value = 1
        seed[1].value = 2
        seed[2].value = 3
        seed[3].value = 4
        seed[4].value = 5
        values.remove(1, 3)

        @assert(values.count == 2)
        @assert(values[0].value == 1)
        @assert(values[1].value == 5)

        values.clear()
        values.free()
    }

    @assert(ArrayDropCount == 5)
}
