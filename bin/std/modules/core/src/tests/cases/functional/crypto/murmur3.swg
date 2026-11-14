#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#[Swag.Safety(.Overflow, false)]
func murmur3Reference(value: u32)->u32
{
    var key = value ^ (value >> 16)
    key *= 0x85EBCA6B'u32
    key ^= key >> 13
    key *= 0xC2B2AE35'u32
    key ^= key >> 16
    return key
}

#[Swag.Safety(.Overflow, false)]
func murmur3Reference(value: u64)->u64
{
    var key = value ^ (value >> 33)
    key *= 0xFF51_AFD7_ED55_8CCD'u64
    key ^= key >> 33
    key *= 0xC4CE_B9FE_1A85_EC53'u64
    key ^= key >> 33
    return key
}

#[Swag.Safety(.Overflow, false)]
func murmur3Reference(a, b: u32)->u32
{
    var na = a * 0xCC9E2D51'u32
    na = Math.ror(na, 17) * 0x1B873593'u32
    var nb = b ^ na
    nb = Math.ror(nb, 19) * 5
    return nb + 0xE6546B64'u32
}

#[Swag.Safety(.Overflow, false)]
func murmur3Reference(a, b: u64)->u64
{
    const K = 0x9DDF_EA08_EB38_2D69'u64
    var na = (a ^ b) * K
    na ^= (na >> 47)
    var nb = (b ^ na) * K
    nb ^= (nb >> 47)
    return nb * K
}

#[Swag.Safety(.Overflow, false)]
func murmur3Reference(key: const [*] u8, len: u64, seed: u64)->u64
{
    const M = 0xC6A4_A793_5BD1_E995'u64
    const R = 47

    var h       = seed ^ (len * M)
    let nblocks = len / 8

    for i in nblocks
    {
        // Independent bytewise little-endian load; do not mirror the production word load.
        var k = 0'u64
        for b in 8 do
            k |= cast(u64, key[i * 8 + b]) << (b * 8)
        k *= M
        k ^= k >> R
        k *= M
        h ^= k
        h *= M
    }

    let data2 = key + nblocks * 8
    switch len & 7
    {
    case 7:
        h ^= cast(u64, data2[6]) << 48
        fallthrough

    case 6:
        h ^= cast(u64, data2[5]) << 40
        fallthrough

    case 5:
        h ^= cast(u64, data2[4]) << 32
        fallthrough

    case 4:
        h ^= cast(u64, data2[3]) << 24
        fallthrough

    case 3:
        h ^= cast(u64, data2[2]) << 16
        fallthrough

    case 2:
        h ^= cast(u64, data2[1]) << 8
        fallthrough

    case 1:
        h ^= cast(u64, data2[0])
        h *= M
    }

    h ^= h >> R
    h *= M
    h ^= h >> R
    return h
}

func assertMurmur3(value: u32)
{
    Swag.require(Hash.murmur3(value) == murmur3Reference(value))
}

func assertMurmur3(value: u64)
{
    Swag.require(Hash.murmur3(value) == murmur3Reference(value))
}

func assertMurmur3Pair(a, b: u32)
{
    Swag.require(Hash.murmur3(a, b) == murmur3Reference(a, b))
}

func assertMurmur3Pair(a, b: u64)
{
    Swag.require(Hash.murmur3(a, b) == murmur3Reference(a, b))
}

func fillMurmur3Pattern(buffer: [..] u8)
{
    var i = 0'u64
    while i < buffer.count
    {
        buffer[i] = cast(u8, ((i * 151 + 7) & 0xFF))
        i         += 1
    }
}

#test
{
    Swag.require(Hash.murmur3(0x12345678'u32, 0'u32) != Hash.murmur3(0x12345678'u32, 1'u32))

    const LeVector: [8] u8 = [1, 2, 3, 4, 5, 6, 7, 8]
    Swag.require(Hash.murmur3(cast(const [*] u8, LeVector.buffer), LeVector.count, 0) == 0x88B2_A580_3544_86B7'u64)

    for value in 65536
    {
        let value32 = cast(u32, value)
        let value64 = cast(u64, value)
        assertMurmur3(value32)
        assertMurmur3(value64)
        assertMurmur3Pair(value32, value32 ^ 0xA5A5_A5A5'u32)
        assertMurmur3Pair(value64, value64 ^ 0xA5A5_A5A5_A5A5_A5A5'u64)
    }

    assertMurmur3(0x7FFF_FFFF'u32)
    assertMurmur3(0x8000_0000'u32)
    assertMurmur3(0xFFFF_FFFF'u32)
    assertMurmur3(0x7FFF_FFFF_FFFF_FFFF'u64)
    assertMurmur3(0x8000_0000_0000_0000'u64)
    assertMurmur3(0xFFFF_FFFF_FFFF_FFFF'u64)

    var backing: [41] u8
    let base   = cast(u64, cast(const [*] u8, backing.buffer))
    let offset = (1 + 8 - (base & 7)) & 7
    var view   = backing[offset to offset + 33]
    fillMurmur3Pattern(view)
    Swag.require((cast(u64, cast(const [*] u8, view.buffer)) & 7) == 1)

    var copiedBacking: [40] u8
    let copiedBase   = cast(u64, cast(const [*] u8, copiedBacking.buffer))
    let copiedOffset = (8 - (copiedBase & 7)) & 7
    var copied       = copiedBacking[copiedOffset to copiedOffset + 33]
    Swag.require((cast(u64, cast(const [*] u8, copied.buffer)) & 7) == 0)
    for i in 33 do
        copied[i] = view[i]

    for length in 34
    {
        let ptr = cast(const [*] u8, view.buffer)
        let alignedPtr = cast(const [*] u8, copied.buffer)
        let hash0 = Hash.murmur3(ptr, length, 0)
        let hash1 = Hash.murmur3(ptr, length, 0x1234_5678_9ABC_DEF0'u64)
        Swag.require(hash0 == murmur3Reference(ptr, length, 0))
        Swag.require(hash1 == murmur3Reference(ptr, length, 0x1234_5678_9ABC_DEF0'u64))
        Swag.require(hash0 == Hash.murmur3(alignedPtr, length, 0))
        Swag.require(hash1 == Hash.murmur3(alignedPtr, length, 0x1234_5678_9ABC_DEF0'u64))
    }
}
