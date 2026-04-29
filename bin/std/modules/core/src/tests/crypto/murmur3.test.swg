#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#[Swag.Safety(.Overflow, false)]
func murmur3Reference(value: u32)->u32
{
    var key = value ^ (value >> 16)
    key *= 0x85ebca6b'u32
    key ^= key >> 13
    key *= 0xc2b2ae35'u32
    key ^= key >> 16
    return key
}

#[Swag.Safety(.Overflow, false)]
func murmur3Reference(value: u64)->u64
{
    var key = value ^ (value >> 33)
    key *= 0xff51_afd7_ed55_8ccd'u64
    key ^= key >> 33
    key *= 0xc4ce_b9fe_1a85_ec53'u64
    key ^= key >> 33
    return key
}

#[Swag.Safety(.Overflow, false)]
func murmur3Reference(a, b: u32)->u32
{
    var na = a * 0xcc9e2d51'u32
    na = Math.ror(na, 17) * 0x1b873593'u32
    var nb = b ^ na
    nb = Math.ror(nb, 19) * 5
    return nb + 0xe6546b64'u32
}

#[Swag.Safety(.Overflow, false)]
func murmur3Reference(a, b: u64)->u64
{
    const K = 0x9ddf_ea08_eb38_2d69'u64
    var na  = (a ^ b) * K
    na ^= (na >> 47)
    var nb = (b ^ na) * K
    nb ^= (nb >> 47)
    return nb * K
}

#[Swag.Safety(.Overflow, false)]
func murmur3Reference(key: const [*] u8, len: u64, seed: u64)->u64
{
    const M = 0xc6a4_a793_5bd1_e995'u64
    const R = 47

    var h = seed ^ (len * M)
    let data = cast(const [*] u64) key
    let nblocks = len / 8

    for i in nblocks
    {
        var k = data[i]
        k *= M
        k ^= k >> R
        k *= M
        h ^= k
        h *= M
    }

    let data2 = cast(const [*] u8) &data[nblocks]
    switch len & 7
    {
    case 7:
        h ^= cast(u64) data2[6] << 48
        fallthrough
    case 6:
        h ^= cast(u64) data2[5] << 40
        fallthrough
    case 5:
        h ^= cast(u64) data2[4] << 32
        fallthrough
    case 4:
        h ^= cast(u64) data2[3] << 24
        fallthrough
    case 3:
        h ^= cast(u64) data2[2] << 16
        fallthrough
    case 2:
        h ^= cast(u64) data2[1] << 8
        fallthrough
    case 1:
        h ^= cast(u64) data2[0]
        h *= M
    }

    h ^= h >> R
    h *= M
    h ^= h >> R
    return h
}

func assertMurmur3(value: u32)
{
    @assert(Hash.murmur3(value) == murmur3Reference(value))
}

func assertMurmur3(value: u64)
{
    @assert(Hash.murmur3(value) == murmur3Reference(value))
}

func assertMurmur3Pair(a, b: u32)
{
    @assert(Hash.murmur3(a, b) == murmur3Reference(a, b))
}

func assertMurmur3Pair(a, b: u64)
{
    @assert(Hash.murmur3(a, b) == murmur3Reference(a, b))
}

func fillMurmur3Pattern(buffer: [..] u8)
{
    var i = 0'u64
    while i < @countof(buffer)
    {
        buffer[i] = cast(u8) ((i * 151 + 7) & 0xff)
        i += 1
    }
}

#test
{
    @assert(Hash.murmur3(0x12345678'u32, 0'u32) != Hash.murmur3(0x12345678'u32, 1'u32))

    for value in 65536
    {
        let value32 = cast(u32) value
        let value64 = cast(u64) value
        assertMurmur3(value32)
        assertMurmur3(value64)
        assertMurmur3Pair(value32, value32 ^ 0xa5a5_a5a5'u32)
        assertMurmur3Pair(value64, value64 ^ 0xa5a5_a5a5_a5a5_a5a5'u64)
    }

    assertMurmur3(0x7fff_ffff'u32)
    assertMurmur3(0x8000_0000'u32)
    assertMurmur3(0xffff_ffff'u32)
    assertMurmur3(0x7fff_ffff_ffff_ffff'u64)
    assertMurmur3(0x8000_0000_0000_0000'u64)
    assertMurmur3(0xffff_ffff_ffff_ffff'u64)

    var data: [33] u8
    fillMurmur3Pattern(data)

    for length in 34
    {
        let ptr = cast(const [*] u8) @dataof(data)
        @assert(Hash.murmur3(ptr, length, 0) == murmur3Reference(ptr, length, 0))
        @assert(Hash.murmur3(ptr, length, 0x1234_5678_9abc_def0'u64) == murmur3Reference(ptr, length, 0x1234_5678_9abc_def0'u64))
    }
}
