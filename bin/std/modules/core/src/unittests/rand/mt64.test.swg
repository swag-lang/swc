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
    @assert(rng.mt[1] == 0xb5347f47116bd3de'u64)
    @assert(rng.mt[311] == 0xc65ae95c45a5d796'u64)

    @assert(rng.nextU64() == 0xc96d191cf6f6aea6'u64)
    @assert(rng.nextU64() == 0x401f7ac78bc80f1c'u64)
    @assert(rng.nextU64() == 0xb5ee8cb6abe457f8'u64)
    @assert(rng.nextU64() == 0xf258d22d4db91392'u64)
    @assert(rng.nextU64() == 0x04eef2b4b5d860cc'u64)
    @assert(rng.mti == 5)
}

#test
{
    var rng: Random.Mt64
    rng.seedU64(123456789)

    @assert(rng.mti == Random.NN)
    @assert(rng.mt[0] == 0x00000000075bcd15'u64)
    @assert(rng.mt[1] == 0xe8739da96f1977b2'u64)
    @assert(rng.mt[311] == 0x96513bca6a404a26'u64)

    @assert(rng.nextU64() == 0x594fa7f19191c80e'u64)
    @assert(rng.nextU64() == 0x44529f3328d35a75'u64)
    @assert(rng.nextU64() == 0x22fb4065f1b6d99f'u64)
    @assert(rng.nextU64() == 0x074f80bb4c13b3c0'u64)
    @assert(rng.nextU64() == 0xde7269257ae40cad'u64)
    @assert(rng.mti == 5)
}

#test
{
    const seed: #nonull const [..] u64 = [0x12345'u64, 0x23456'u64, 0x34567'u64, 0x45678'u64]
    var rng: Random.Mt64
    rng.seedU64(seed)

    @assert(rng.mti == Random.NN)
    @assert(rng.mt[0] == 0x8000000000000000'u64)
    @assert(rng.mt[1] == 0xa53da00c269cd27c'u64)
    @assert(rng.mt[311] == 0x81a384fb290849cd'u64)

    @assert(rng.nextU64() == 0x64d79b552a559d7f'u64)
    @assert(rng.nextU64() == 0x44a572665a6ee240'u64)
    @assert(rng.nextU64() == 0xeb2bf6dc3d72135c'u64)
    @assert(rng.nextU64() == 0xe3836981f9f82ea0'u64)
    @assert(rng.nextU64() == 0x43a38212350ee392'u64)
    @assert(rng.mti == 5)
}
