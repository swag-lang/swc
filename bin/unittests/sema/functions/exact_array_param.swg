#global private

alias ExactArrayParamDigest = [16] u8

func exactArrayParamSum(values: [4] s32)->s32
{
    #assert(#typeof(values) == [4] s32)
    #assert(#nameof(#typeof(&values)) == "[*] [4] s32")
    return values[0] + values[3]
}

func exactArrayParamFill(digest: ExactArrayParamDigest, seed: u8)
{
    #assert(#typeof(digest) == ExactArrayParamDigest)
    for i in @countof(digest) do
        digest[i] = seed + cast(u8) i
}

func exactGridParamRead(grid: [2, 3] s16)->s16
{
    #assert(#typeof(grid[0]) == [3] s16)
    return grid[1, 2]
}

func(T) exactArrayParamTail(values: [4] T)->T
{
    #assert(#typeof(values) == [4] T)
    #assert(#nameof(#typeof(&values)) == "[*] [4] u16")
    return values[3]
}

#test
{
    var values: [4] s32 = [1, 2, 3, 4]
    let total = exactArrayParamSum(values)
    let totalPlus = total + 1
    #assert(#typeof(totalPlus) == s32)

    var digest: ExactArrayParamDigest = undefined
    exactArrayParamFill(digest, 10'u8)
    let firstByte = digest[0]
    let lastByte  = digest[15]
    #assert(#typeof(firstByte) == u8)
    #assert(#typeof(lastByte) == u8)

    var grid: [2, 3] s16 = [[1, 2, 3], [4, 5, 6]]
    let tail = exactGridParamRead(grid)
    let tailPlus = tail + 1's16
    #assert(#typeof(tailPlus) == s16)
}

#test
{
    let reader = func(values: [4] s32)->s32
    {
        #assert(#typeof(values) == [4] s32)
        #assert(#nameof(#typeof(&values)) == "[*] [4] s32")
        return values[1] + values[2]
    }

    var values: [4] s32 = [5, 6, 7, 8]
    let combined = reader(values)
    let exactTail = exactArrayParamTail([9'u16, 10'u16, 11'u16, 12'u16])
    #assert(#typeof(combined) == s32)
    #assert(#typeof(exactTail) == u16)
}
