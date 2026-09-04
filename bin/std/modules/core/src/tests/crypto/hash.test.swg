#global if #command == Swag.CompilerCommand.Test

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

    Swag.assert(Hash.hash32(TEXT) == Hash.hashBytes32(TEXT))
    Swag.assert(Hash.hash64(TEXT) == Hash.murmur3(TEXT.buffer, TEXT.count, 0))

    Swag.assert(Hash.hash32(onlyHash32) == EXPECTED_ONLY_HASH32_32)
    Swag.assert(Hash.hash64(onlyHash32) == EXPECTED_ONLY_HASH32_64)

    Swag.assert(Hash.hash32(onlyHash64) == EXPECTED_ONLY_HASH64_32)
    Swag.assert(Hash.hash64(onlyHash64) == EXPECTED_ONLY_HASH64_64)

    Swag.assert(Hash.hash32(bothHash) == EXPECTED_BOTH_HASH32)
    Swag.assert(Hash.hash64(bothHash) == EXPECTED_BOTH_HASH64)
}

#assert(Hash.hashBytes32("abc") == Hash.hashBytes32("abc"))
#assert(Hash.hashBytes32("abc") != Hash.hashBytes32("abd"))
#assert(Hash.hashBytes32("") != Hash.hashBytes32("a"))

// 'hashBytes32' reads 8 bytes at a time and overlaps the tail rather than stepping
// through it. Cover every length branch, and prove the overlap never reaches past
// the range it was given.
#test
{
    const Lengths = [0'u64, 1, 2, 3, 4, 5, 6, 7, 8, 9, 15, 16, 17, 31, 32, 33, 64]

    var source: [80] u8
    for i in 80'u64 do
        source[i] = cast(u8) ((i * 7 + 13) & 0xFF)

    var seen: [Lengths.count] u32

    for slot in Lengths.count
    {
        let length = Lengths[slot]
        let view   = Swag.makeSlice(&source[0], length)
        let hashed = Hash.hashBytes32(view)

        // Same bytes, same hash
        Swag.assert(Hash.hashBytes32(view) == hashed)

        // Bytes beyond 'length' must not take part: same prefix in a differently
        // filled buffer has to produce the same value
        var padded: [80] u8
        Memory.set(&padded[0], 0xAA'u8, 80)
        Memory.copy(&padded[0], &source[0], length)
        Swag.assert(Hash.hashBytes32(Swag.makeSlice(&padded[0], length)) == hashed)

        // Flipping the last byte has to change the hash
        if length
        {
            padded[length - 1] ^= 0xFF
            Swag.assert(Hash.hashBytes32(Swag.makeSlice(&padded[0], length)) != hashed)
        }

        seen[slot] = hashed
    }

    // Distinct prefixes give distinct hashes
    for i in Lengths.count
    {
        for j in Lengths.count
        {
            if j > i do
                Swag.assert(seen[i] != seen[j])
        }
    }
}
