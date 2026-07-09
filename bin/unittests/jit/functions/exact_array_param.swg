#global private

alias ExactArrayParamJitDigest = [16] u8

func rotateExactArray(values: [4] s32)
{
    let first = values[0]
    values[0] = values[1]
    values[1] = values[2]
    values[2] = values[3]
    values[3] = first
}

func fillExactDigest(digest: ExactArrayParamJitDigest, seed: u8)
{
    for i in @countof(digest) do
        digest[i] = seed + cast(u8) i
}

func(T) reverseExactPair(values: [2] T)
{
    let first = values[0]
    values[0] = values[1]
    values[1] = first
}

struct ExactArrayParamJitWriter
{
    delta: s32
}

impl ExactArrayParamJitWriter
{
    mtd write(values: [4] s32)
    {
        for i in 4 do
            values[i] += .delta + cast(s32) i
    }
}

#test
{
    var values: [4] s32 = [11, 22, 33, 44]
    rotateExactArray(values)
    @assert(values[0] == 22)
    @assert(values[1] == 33)
    @assert(values[2] == 44)
    @assert(values[3] == 11)
}

#test
{
    var digest: ExactArrayParamJitDigest = undefined
    fillExactDigest(digest, 9'u8)

    var checksum: s32 = 0
    for value in digest do
        checksum += cast(s32) value

    @assert(digest[0] == 9'u8)
    @assert(digest[15] == 24'u8)
    @assert(checksum == 264)
}

#test
{
    var values: [4] s32 = [1, 10, 100, 1000]
    var writer = ExactArrayParamJitWriter{delta: 5}
    writer.write(values)
    @assert(values[0] == 6)
    @assert(values[1] == 16)
    @assert(values[2] == 107)
    @assert(values[3] == 1008)
}

#test
{
    let patch = func(values: [4] s32)
    {
        values[0] += 100
        values[3] -= 7
    }

    var values: [4] s32 = [3, 6, 9, 12]
    patch(values)
    @assert(values[0] == 103)
    @assert(values[1] == 6)
    @assert(values[2] == 9)
    @assert(values[3] == 5)
}

#test
{
    var pair: [2] u16 = [7'u16, 42'u16]
    reverseExactPair(pair)
    @assert(pair[0] == 42'u16)
    @assert(pair[1] == 7'u16)
}
