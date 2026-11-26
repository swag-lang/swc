// @LICENCE: LicenseRef-Public-Domain
// @ORIGIN: MurmurHash3 by Austin Appleby, https://github.com/aappleby/smhasher
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#murmurhash3

#global namespace Hash

using Swag

// Returns the MurmurHash3 finalizer mix of the integer `h`.
//
// Every input bit affects every output bit, which suits hash-table keys that are already integers.
#[Inline, Safety(.All, false)]
public func murmur3(h: u32)->u32
{
    var key = h ^ (h >> 16)
    key *= 0x85EBCA6B
    key ^= key >> 13
    key *= 0xC2B2AE35
    key ^= key >> 16
    return key
}

// Returns the MurmurHash3 64-bit finalizer mix of the integer `h`.
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

// Combines the hashes `a` and `b` into one hash.
#[Inline, Safety(.All, false)]
public func murmur3(a, b: u32)->u32
{
    var na = a * 0xCC9E2D51
    na = Math.ror(na, 17) * 0x1B873593
    var nb = b ^ na
    nb = Math.ror(nb, 19) * 5
    return nb + 0xE6546B64
}

// Combines the 64-bit hashes `a` and `b` into one hash.
#[Safety(.All, false)]
public func murmur3(a, b: u64)->u64
{
    const K = 0x9DDFEA08EB382D69
    var na = (a ^ b) * K
    na ^= (na >> 47)
    var nb = (b ^ na) * K
    nb ^= (nb >> 47)
    return nb * K
}

// Returns a hash of the `len` bytes at `key`, seeded with `seed`.
//
// The byte hash is MurmurHash64A, which reads little-endian eight-byte blocks.
#[Safety(.All, false)]
public func murmur3(key: const [*] u8, len: u64, seed: u64)->u64
{
    const m = 0xC6A4A7935BD1E995'u64
    const r = 47

    var h = seed ^ (len * m)

    var words = cast(const [*] u64, key)
    let end   = words + len / 8
    while words != end
    {
        var k = Math.littleEndianToNative(words[0])
        k     *= m
        k     ^= k >> r
        k     *= m
        h     ^= k
        h     *= m
        words += 1
    }

    let tail = cast(const [*] u8, words)
    switch len & 7
    {
    case 7:
        h ^= cast(u64, tail[6]) << 48
        fallthrough

    case 6:
        h ^= cast(u64, tail[5]) << 40
        fallthrough

    case 5:
        h ^= cast(u64, tail[4]) << 32
        fallthrough

    case 4:
        h ^= cast(u64, tail[3]) << 24
        fallthrough

    case 3:
        h ^= cast(u64, tail[2]) << 16
        fallthrough

    case 2:
        h ^= cast(u64, tail[1]) << 8
        fallthrough

    case 1:
        h ^= cast(u64, tail[0])
        h *= m
    }

    h ^= h >> r
    h *= m
    h ^= h >> r

    return h
}
