#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    @assert(Random.NN == 312)

    var rng: Random.Mt64
    @assert(rng.mti == 0)
    @assert(rng.mt[0] == 0)

    @assert(rng.nextU64() == 0)
    @assert(rng.nextU64() == 0)
    @assert(rng.nextU64() == 0)
    @assert(rng.mti == 3)
}

#test
{
    var rng: Random.Mt64
    rng.seedU64(5489)

    @assert(rng.mti == Random.NN)
    @assert(rng.mt[0] == 0x0000000000001571'u64)
    @assert(rng.mt[1] == 0xB5347F47116BD3DE'u64)
    @assert(rng.mt[311] == 0xC65AE95C45A5D796'u64)

    @assert(rng.nextU64() == 0xC96D191CF6F6AEA6'u64)
    @assert(rng.nextU64() == 0x401F7AC78BC80F1C'u64)
    @assert(rng.nextU64() == 0xB5EE8CB6ABE457F8'u64)
    @assert(rng.nextU64() == 0xF258D22D4DB91392'u64)
    @assert(rng.nextU64() == 0x04EEF2B4B5D860CC'u64)
    @assert(rng.mti == 5)
}

#test
{
    var rng: Random.Mt64
    rng.seedU64(123456789)

    @assert(rng.mti == Random.NN)
    @assert(rng.mt[0] == 0x00000000075BCD15'u64)
    @assert(rng.mt[1] == 0xE8739DA96F1977B2'u64)
    @assert(rng.mt[311] == 0x96513BCA6A404A26'u64)

    @assert(rng.nextU64() == 0x594FA7F19191C80E'u64)
    @assert(rng.nextU64() == 0x44529F3328D35A75'u64)
    @assert(rng.nextU64() == 0x22FB4065F1B6D99F'u64)
    @assert(rng.nextU64() == 0x074F80BB4C13B3C0'u64)
    @assert(rng.nextU64() == 0xDE7269257AE40CAD'u64)
    @assert(rng.mti == 5)
}

#test
{
    const seed: const [..] u64 = [0x12345'u64, 0x23456'u64, 0x34567'u64, 0x45678'u64]
    var rng: Random.Mt64
    rng.seedU64(seed)

    @assert(rng.mti == Random.NN)
    @assert(rng.mt[0] == 0x8000000000000000'u64)
    @assert(rng.mt[1] == 0xA53DA00C269CD27C'u64)
    @assert(rng.mt[311] == 0x81A384FB290849CD'u64)

    @assert(rng.nextU64() == 0x64D79B552A559D7F'u64)
    @assert(rng.nextU64() == 0x44A572665A6EE240'u64)
    @assert(rng.nextU64() == 0xEB2BF6DC3D72135C'u64)
    @assert(rng.nextU64() == 0xE3836981F9F82EA0'u64)
    @assert(rng.nextU64() == 0x43A38212350EE392'u64)
    @assert(rng.mti == 5)
}
