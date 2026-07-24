/*
    :LICENCE
    MurmurHash3 was written by Austin Appleby, and is placed in the public
    domain. The author hereby disclaims copyright to this source code.
*/

#global namespace Hash

using Swag

#[Safety(.All, false)]
public func murmur3(h: u32)->u32
{
    var key = h ^ (h >> 16)
    key *= 0x85EBCA6B
    key ^= key >> 13
    key *= 0xC2B2AE35
    key ^= key >> 16
    return key
}

#[Safety(.All, false)]
public func murmur3(h: u64)->u64
{
    var key = h ^ (h >> 33)
    key *= 0xFF51AFD7ED558CCD
    key ^= key >> 33
    key *= 0xC4CEB9FE1A85EC53
    key ^= key >> 33
    return key
}

#[Safety(.All, false)]
public func murmur3(a, b: u32)->u32
{
    var na = a * 0xCC9E2D51
    na = Math.ror(na, 17) * 0x1B873593
    var nb = b ^ na
    nb = Math.ror(nb, 19) * 5
    return nb + 0xE6546B64
}

#[Safety(.All, false)]
public func murmur3(a, b: u64)->u64
{
    const K = 0x9DDFEA08EB382D69
    var na  = (a ^ b) * K
    na ^= (na >> 47)
    var nb = (b ^ na) * K
    nb ^= (nb >> 47)
    return nb * K
}

#[Safety(.All, false)]
public func murmur3(key: const [*] u8, len: u64, seed: u64)->u64
{
    const m = 0xC6A4A7935BD1E995'u64
    const r = 47

    var h = seed ^ (len * m)

    let data    = notnull cast(#null const [*] u64) key
    let nblocks = len / 8

    for [i] in nblocks
    {
        var k = data[i]
        k *= m
        k ^= k >> r
        k *= m
        h ^= k
        h *= m
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
        h *= m
    }

    h ^= h >> r
    h *= m
    h ^= h >> r

    return h
}
