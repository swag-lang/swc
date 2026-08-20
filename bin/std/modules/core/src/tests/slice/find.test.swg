#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#assert(Slice.contains([1'u8, 2, 3], 2'u8))
#assert(!Slice.contains([1'u8, 2, 3], 4'u8))

#test
{
    var empty:  #null [..] s32 = null
    let values: [6] s32        = [1, 3, 5, 7, 9, 11]

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

    @assert(Slice.findSubslice(values, [1, 2]) == 0)
    @assert(Slice.findSubslice(values, [3, 4, 5]) == 2)
    @assert(Slice.findSubslice(values, [6, 7]) == 5)
    @assert(Slice.findSubslice(values, [7, 8]) == Swag.U64.Max)
    @assert(Slice.findSubslice(values, values) == 0)
    @assert(Slice.findSubslice(values, @mkslice(@dataof(values), 0)) == 0)
}

#test
{
    var emptyA: #null [..] s32 = null
    var emptyB: #null [..] s32 = null
    let left:   [4] s32        = [1, 2, 3, 4]
    let same:   [4] s32        = [1, 2, 3, 4]
    let other:  [4] s32        = [1, 2, 4, 3]

    @assert(Slice.equals(emptyA, emptyB))
    @assert(Slice.equals(left, same))
    @assert(!Slice.equals(left, other))
    @assert(!Slice.equals(left, [1, 2, 3]))
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
        @assert(Slice.findLinear(values, 0xE7'u8) == position)
    }

    @assert(Slice.findLinear(values, 0xFF'u8) == Swag.U64.Max)

    for position in 96
    {
        for &value in values do
            value[] = 0x11
        values[position] = 0xE7
        @assert(Slice.contains(values, 0xE7'u8))
        @assert(!Slice.contains(values, 0xFF'u8))
    }

    let needle: [5] u8 = [1, 2, 3, 4, 5]
    for position in 80
    {
        for &value in values do
            value[] = 0
        for i in @countof(needle) do
            values[position + i] = needle[i]
        @assert(Slice.findSubslice(values, needle) == position)
    }

    for &value in values do
        value[] = 0x11
    @assert(Slice.findSubslice(values, [0x11'u8, 0x12]) == Swag.U64.Max)

    var same = values
    @assert(Slice.equals(values, same))
    for position in 96
    {
        same[position] ^= 0xFF
        @assert(!Slice.equals(values, same))
        same[position] ^= 0xFF
    }

    @assert(Slice.equals(values[1 until 95], same[1 until 95]))
}
