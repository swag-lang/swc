#global #if #command == Swag.CompilerCommand.Test
using Swag

namespace HashTestTypes
{
    struct OnlyHash32
    {
        value: u32
    }

    impl Hash.IHash32 for OnlyHash32
    {
        mtd const impl compute()->u32
        {
            return 0x1234_5678'u32 + .value
        }
    }

    struct OnlyHash64
    {
        value: u64
    }

    impl Hash.IHash64 for OnlyHash64
    {
        mtd const impl compute()->u64
        {
            return 0x0123_4567_89AB_CDEF'u64 + .value
        }
    }

    struct BothHash
    {
        value: u32
    }

    impl Hash.IHash32 for BothHash
    {
        mtd const impl compute()->u32
        {
            return 0x0BAD_F00D'u32 + .value
        }
    }

    impl Hash.IHash64 for BothHash
    {
        mtd const impl compute()->u64
        {
            return 0x0123_4567_DEAD_BEEF'u64 + .value
        }
    }
}

const TEXT        = "abc"
const ONLY_HASH32 = HashTestTypes.OnlyHash32{value: 3}
const ONLY_HASH64 = HashTestTypes.OnlyHash64{value: 5}
const BOTH_HASH   = HashTestTypes.BothHash{value: 7}

const EXPECTED_ONLY_HASH32_32 = 0x1234_567B'u32
const EXPECTED_ONLY_HASH32_64 = 0x1234_567B'u64
const EXPECTED_ONLY_HASH64_32 = 0x89AB_CDF4'u32
const EXPECTED_ONLY_HASH64_64 = 0x0123_4567_89AB_CDF4'u64
const EXPECTED_BOTH_HASH32    = 0x0BAD_F014'u32
const EXPECTED_BOTH_HASH64    = 0x0123_4567_DEAD_BEF6'u64

#assert(#typeof(HashTestTypes.OnlyHash32).fullname == #fullnameof(HashTestTypes.OnlyHash32))
#assert(#typeof(HashTestTypes.OnlyHash64).fullname == #fullnameof(HashTestTypes.OnlyHash64))
#assert(#typeof(HashTestTypes.BothHash).fullname == #fullnameof(HashTestTypes.BothHash))

#assert(Hash.hash32(ONLY_HASH32) == EXPECTED_ONLY_HASH32_32)
#assert(Hash.hash64(ONLY_HASH32) == EXPECTED_ONLY_HASH32_64)

#assert(Hash.hash32(ONLY_HASH64) == EXPECTED_ONLY_HASH64_32)
#assert(Hash.hash64(ONLY_HASH64) == EXPECTED_ONLY_HASH64_64)

#assert(Hash.hash32(BOTH_HASH) == EXPECTED_BOTH_HASH32)
#assert(Hash.hash64(BOTH_HASH) == EXPECTED_BOTH_HASH64)

#test
{
    let onlyHash32 = HashTestTypes.OnlyHash32{value: 3}
    let onlyHash64 = HashTestTypes.OnlyHash64{value: 5}
    let bothHash   = HashTestTypes.BothHash{value: 7}

    @assert(Hash.hash32(TEXT) == Hash.Crc32.compute(TEXT))
    @assert(Hash.hash64(TEXT) == Hash.murmur3(@dataof(TEXT), @countof(TEXT), 0))

    @assert(Hash.hash32(onlyHash32) == EXPECTED_ONLY_HASH32_32)
    @assert(Hash.hash64(onlyHash32) == EXPECTED_ONLY_HASH32_64)

    @assert(Hash.hash32(onlyHash64) == EXPECTED_ONLY_HASH64_32)
    @assert(Hash.hash64(onlyHash64) == EXPECTED_ONLY_HASH64_64)

    @assert(Hash.hash32(bothHash) == EXPECTED_BOTH_HASH32)
    @assert(Hash.hash64(bothHash) == EXPECTED_BOTH_HASH64)
}
