#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#assert(Slice.contains([1'u8, 2, 3], 2'u8))
#assert(not Slice.contains([1'u8, 2, 3], 4'u8))

#test
{
    var empty:  [..] s32? = null
    let values: [6] s32   = [1, 3, 5, 7, 9, 11]

    Swag.require(Slice.findSorted(empty, 1) == Swag.U64.Max)
    Swag.require(Slice.findSorted(values, 1) == 0)
    Swag.require(Slice.findSorted(values, 7) == 3)
    Swag.require(Slice.findSorted(values, 11) == 5)
    Swag.require(Slice.findSorted(values, 4) == Swag.U64.Max)
    Swag.require(Slice.containsSorted(values, 9))
    Swag.require(not Slice.containsSorted(values, 8))
}

#test
{
    var emptyNumbers: [..] s32? = null
    var emptyBytes:   [..] u8?  = null
    let duplicates:   [5] s32   = [1, 3, 3, 3, 7]

    Swag.require(Slice.findLinear(emptyNumbers, 1) == Swag.U64.Max)
    Swag.require(not Slice.contains(emptyNumbers, 1))
    Swag.require(Slice.findLinear(emptyBytes, 1'u8) == Swag.U64.Max)
    Swag.require(not Slice.contains(emptyBytes, 1'u8))

    let found = Slice.findSorted(duplicates, 3)
    Swag.require(found >= 1 and found <= 3 and duplicates[found] == 3)
    Swag.require(Slice.containsSorted(duplicates, 3))
}

#test
{
    let values: [4] string = ["alpha", "beta", "gamma", "beta"]

    Swag.require(Slice.findLinear(values, "alpha") == 0)
    Swag.require(Slice.findLinear(values, "beta") == 1)
    Swag.require(Slice.findLinear(values, "missing") == Swag.U64.Max)

    Swag.require(Slice.contains(values, "gamma"))
    Swag.require(not Slice.contains(values, "delta"))
}

#test
{
    let values: [7] s32 = [1, 2, 3, 4, 5, 6, 7]

    Swag.require(Slice.findSubslice(values, [1, 2]) == 0)
    Swag.require(Slice.findSubslice(values, [3, 4, 5]) == 2)
    Swag.require(Slice.findSubslice(values, [6, 7]) == 5)
    Swag.require(Slice.findSubslice(values, [7, 8]) == Swag.U64.Max)
    Swag.require(Slice.findSubslice(values, values) == 0)
    Swag.require(Slice.findSubslice(values, values[until 0]) == 0)
}

#test
{
    let values: [3] s32 = [4, 4, 4]
    let tooLong: [4] s32 = [4, 4, 4, 4]
    let empty = values[until 0]
    let overlapping: [5] s32 = [1, 1, 1, 2, 1]

    Swag.require(Slice.findSubslice(empty, empty) == 0)
    Swag.require(Slice.findSubslice(values, tooLong) == Swag.U64.Max)
    Swag.require(Slice.findSubslice(values, [4, 4]) == 0)
    Swag.require(Slice.findSubslice(overlapping, [1, 1, 2]) == 1)
}

// The byte specialization handles empty and oversized inputs and a match at the last start.
#test
{
    let backing: [1] u8 = [0]
    let empty = backing[until 0]
    let tooLong: [1] u8 = [1]

    Swag.require(Slice.findSubslice(empty, empty) == 0)
    Swag.require(Slice.findSubslice(empty, tooLong) == Swag.U64.Max)

    var values: [24] u8
    for &value in values do
        value[] = 0x11
    let needle: [5] u8 = [1, 2, 3, 4, 5]
    for i in needle.count do
        values[19 + i] = needle[i]

    Swag.require(Slice.findSubslice(values, needle) == 19)
}

#test
{
    var emptyA: [..] s32? = null
    var emptyB: [..] s32? = null
    let left:   [4] s32   = [1, 2, 3, 4]
    let same:   [4] s32   = [1, 2, 3, 4]
    let other:  [4] s32   = [1, 2, 4, 3]

    Swag.require(Slice.equals(emptyA, emptyB))
    Swag.require(Slice.equals(left, same))
    Swag.require(not Slice.equals(left, other))
    Swag.require(not Slice.equals(left, [1, 2, 3]))
}

// Byte overloads cover every lane, unaligned starts, vector tails, and long
// candidates without changing the generic operation family.
#test
{
    var values: [96] u8
    for position in 96
    {
        for &value in values do
            value[] = 0x11
        values[position] = 0xE7
        Swag.require(Slice.findLinear(values, 0xE7'u8) == position)
    }

    Swag.require(Slice.findLinear(values, 0xFF'u8) == Swag.U64.Max)

    for position in 96
    {
        for &value in values do
            value[] = 0x11
        values[position] = 0xE7
        Swag.require(Slice.contains(values, 0xE7'u8))
        Swag.require(not Slice.contains(values, 0xFF'u8))
    }

    let needle: [5] u8 = [1, 2, 3, 4, 5]
    for position in 80
    {
        for &value in values do
            value[] = 0
        for i in needle.count do
            values[position + i] = needle[i]
        Swag.require(Slice.findSubslice(values, needle) == position)
    }

    // Several candidate starts in one vector must be checked until the full needle matches.
    for &value in values do
        value[] = 0
    values[0] = 1
    values[1] = 2
    values[16] = 1
    values[17] = 2
    for i in needle.count do
        values[31 + i] = needle[i]
    Swag.require(Slice.findSubslice(values, needle) == 31)

    for &value in values do
        value[] = 0x11
    Swag.require(Slice.findSubslice(values, [0x11'u8, 0x12]) == Swag.U64.Max)

    var same = values
    Swag.require(Slice.equals(values, same))
    for position in 96
    {
        same[position] ^= 0xFF
        Swag.require(not Slice.equals(values, same))
        same[position] ^= 0xFF
    }

    Swag.require(Slice.equals(values[1 until 95], same[1 until 95]))
}
