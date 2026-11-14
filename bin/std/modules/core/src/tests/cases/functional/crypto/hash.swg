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
        mtd const impl compute()->u32 => 0x1234_5678'u32 + .value
    }

    struct OnlyHash64
    {
        value: u64
    }

    impl Hash.IHash64 for OnlyHash64
    {
        mtd const impl compute()->u64 => 0x0123_4567_89AB_CDEF'u64 + .value
    }

    struct BothHash
    {
        value: u32
    }

    impl Hash.IHash32 for BothHash
    {
        mtd const impl compute()->u32 => 0x0BAD_F00D'u32 + .value
    }

    impl Hash.IHash64 for BothHash
    {
        mtd const impl compute()->u64 => 0x0123_4567_DEAD_BEEF'u64 + .value
    }

    struct StringHolder
    {
        text: string
        tag:  s64
    }

    struct OwnedStringHolder
    {
        text: Core.String
        tag:  s64
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

    Swag.require(Hash.hash32(TEXT) == Hash.hashBytes32(TEXT))
    Swag.require(Hash.hash64(TEXT) == Hash.murmur3(TEXT.buffer, TEXT.count, 0))

    Swag.require(Hash.hash32(onlyHash32) == EXPECTED_ONLY_HASH32_32)
    Swag.require(Hash.hash64(onlyHash32) == EXPECTED_ONLY_HASH32_64)

    Swag.require(Hash.hash32(onlyHash64) == EXPECTED_ONLY_HASH64_32)
    Swag.require(Hash.hash64(onlyHash64) == EXPECTED_ONLY_HASH64_64)

    Swag.require(Hash.hash32(bothHash) == EXPECTED_BOTH_HASH32)
    Swag.require(Hash.hash64(bothHash) == EXPECTED_BOTH_HASH64)

    Swag.require(Hash.hash32(false) != Hash.hash32(true))
    Swag.require(Hash.hash64(false) != Hash.hash64(true))
}

#test
{
    // Struct equality compares string content, so hashing must not include the buffer address.
    var left:  [4] u8 = ['s', 'a', 'm', 'e']
    var right: [4] u8 = ['s', 'a', 'm', 'e']
    let leftText  = cast(string, Swag.makeSlice(cast(const [*] u8, left.buffer), 4))
    let rightText = cast(string, Swag.makeSlice(cast(const [*] u8, right.buffer), 4))
    Swag.require(leftText.buffer != rightText.buffer)
    let leftValue = HashTestTypes.StringHolder{text: leftText, tag: 7}
    let rightValue = HashTestTypes.StringHolder{text: rightText, tag: 7}
    Swag.require(leftValue == rightValue)
    Swag.require(Hash.hash32(leftValue) == Hash.hash32(rightValue))
    Swag.require(Hash.hash64(leftValue) == Hash.hash64(rightValue))

    // Core.String owns a separate buffer but compares by its text as well.
    let leftOwned  = Core.String.from("same")
    let rightOwned = Core.String.from("same")
    Swag.require(leftOwned.toSlice().buffer != rightOwned.toSlice().buffer)
    Swag.require(leftOwned == rightOwned)
    Swag.require(Hash.hash32(leftOwned) == Hash.hash32(rightOwned))
    Swag.require(Hash.hash64(leftOwned) == Hash.hash64(rightOwned))

    let leftOwnedValue  = HashTestTypes.OwnedStringHolder{text: Core.String.from("same"), tag: 9}
    let rightOwnedValue = HashTestTypes.OwnedStringHolder{text: Core.String.from("same"), tag: 9}
    Swag.require(leftOwnedValue.text.buffer != rightOwnedValue.text.buffer)
    Swag.require(leftOwnedValue == rightOwnedValue)
    Swag.require(Hash.hash32(leftOwnedValue) == Hash.hash32(rightOwnedValue))
    Swag.require(Hash.hash64(leftOwnedValue) == Hash.hash64(rightOwnedValue))
}

#assert(Hash.hashBytes32("abc") == Hash.hashBytes32("abc"))
#assert(Hash.hashBytes32("abc") != Hash.hashBytes32("abd"))
#assert(Hash.hashBytes32("") != Hash.hashBytes32("a"))

// 'hashBytes32' reads 8 bytes at a time and overlaps the tail rather than stepping
// through it. Cover every length branch, and prove the overlap never reaches past
// the range it was given.
#test
{
    // A subview may start at any byte offset. Exercise misaligned 32-bit and 64-bit
    // reads for both the head and overlapping tail paths.
    var source: [72] u8
    let base   = cast(u64, cast(const [*] u8, source.buffer))
    let offset = (1 + 8 - (base & 7)) & 7
    var view   = source[offset to offset + 64]
    for i in view.count do
        view[i] = cast(u8, ((i * 29 + 7) & 0xFF))
    Swag.require((cast(u64, cast(const [*] u8, view.buffer)) & 7) == 1)

    var copied: [64] u8
    Memory.copy(cast([*] void, &copied[0]), cast(const [*] void, view.buffer), view.count)
    for length in 4 to 64
    {
        Swag.require(Hash.hashBytes32(view[until length]) == Hash.hashBytes32(copied[until length]))
    }
}

#test
{
    const Lengths = [0'u64, 1, 2, 3, 4, 5, 6, 7, 8, 9, 15, 16, 17, 31, 32, 33, 64]

    var source: [80] u8
    for i in 80'u64 do
        source[i] = cast(u8, ((i * 7 + 13) & 0xFF))

    var seen: [Lengths.count] u32

    for slot in Lengths.count
    {
        let length = Lengths[slot]
        let view   = source[until length]
        let hashed = Hash.hashBytes32(view)

        // Same bytes, same hash
        Swag.require(Hash.hashBytes32(view) == hashed)

        // Bytes beyond 'length' must not take part: same prefix in a differently
        // filled buffer has to produce the same value
        var padded: [80] u8
        Memory.set(&padded[0], 0xAA'u8, 80)
        Memory.copy(&padded[0], &source[0], length)
        Swag.require(Hash.hashBytes32(padded[until length]) == hashed)

        // Flipping the last byte has to change the hash
        if length
        {
            padded[length - 1] ^= 0xFF
            Swag.require(Hash.hashBytes32(padded[until length]) != hashed)
        }

        seen[slot] = hashed
    }

    // Distinct prefixes give distinct hashes
    for i in Lengths.count
    {
        for j in Lengths.count
        {
            if j > i do
                Swag.require(seen[i] != seen[j])
        }
    }
}
