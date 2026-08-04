// Open-addressing hash map with byte-slice keys, written from scratch.
// This is the pure-Swag stand-in for a Python 'dict', a Lua table or a JS 'Map':
// keys are (offset, length) views into a caller-owned byte arena.

struct ByteMap
{
    keyOff: [*] u64
    keyLen: [*] u64
    val:    [*] u64
    used:   [*] u8
    base:   [*] u8
    mask:   u64
    count:  u64
}

func mapInit(m: *ByteMap, capacity: u64, base: [*] u8)
{
    m.keyOff = cast([*] u64) (@alloc(capacity * #sizeof(u64)))!
    m.keyLen = cast([*] u64) (@alloc(capacity * #sizeof(u64)))!
    m.val    = cast([*] u64) (@alloc(capacity * #sizeof(u64)))!
    m.used   = cast([*] u8) @alloc(capacity)!
    @memset(m.used, 0'u8, capacity)
    m.base  = base
    m.mask  = capacity - 1
    m.count = 0
}

func mapFree(m: *ByteMap)
{
    @free(m.used)
    @free(m.val)
    @free(m.keyLen)
    @free(m.keyOff)
}

// Returns the table index holding the key, or the free slot it should occupy.
func mapProbe(m: *ByteMap, off, len: u64)->u64
{
    var h = 2166136261'u64
    for [i] in len
    {
        h ^= cast(u64) m.base[off + i]
        h = (h * 16777619) & 0xFFFFFFFF
    }

    var idx = h & m.mask
    while m.used[idx] != 0
    {
        if m.keyLen[idx] == len and @memcmp(&m.base[m.keyOff[idx]], &m.base[off], len) == 0 do
            return idx
        idx = (idx + 1) & m.mask
    }

    return idx
}

func mapClaim(m: *ByteMap, idx, off, len, value: u64)
{
    m.used[idx]   = 1
    m.keyOff[idx] = off
    m.keyLen[idx] = len
    m.val[idx]    = value
    m.count += 1
}
