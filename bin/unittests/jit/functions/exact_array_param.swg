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
    for i in digest.count do
        digest[i] = seed + cast(u8, i)
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
            values[i] += .delta + cast(s32, i)
    }
}

#test
{
    var values: [4] s32 = [11, 22, 33, 44]
    rotateExactArray(values)
    Swag.require(values[0] == 22)
    Swag.require(values[1] == 33)
    Swag.require(values[2] == 44)
    Swag.require(values[3] == 11)
}

#test
{
    var digest: ExactArrayParamJitDigest
    fillExactDigest(digest, 9'u8)

    var checksum: s32 = 0
    for value in digest do
        checksum += cast(s32, value)

    Swag.require(digest[0] == 9'u8)
    Swag.require(digest[15] == 24'u8)
    Swag.require(checksum == 264)
}

#test
{
    var values: [4] s32 = [1, 10, 100, 1000]
    var writer = ExactArrayParamJitWriter{delta: 5}
    writer.write(values)
    Swag.require(values[0] == 6)
    Swag.require(values[1] == 16)
    Swag.require(values[2] == 107)
    Swag.require(values[3] == 1008)
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
    Swag.require(values[0] == 103)
    Swag.require(values[1] == 6)
    Swag.require(values[2] == 9)
    Swag.require(values[3] == 5)
}

#test
{
    var pair: [2] u16 = [7'u16, 42'u16]
    reverseExactPair(pair)
    Swag.require(pair[0] == 42'u16)
    Swag.require(pair[1] == 7'u16)
}
