module bytemap;

import common;
struct ByteMap
{
    u64* keyOff;
    u64* keyLen;
    u64* val;
    u8*  used;
    u8*  base;
    u64  mask;
    u64  count;
};

void mapInit(ByteMap* m, u64 capacity, u8* base)
{
    m.keyOff = cast(u64*) xalloc(capacity * u64.sizeof);
    m.keyLen = cast(u64*) xalloc(capacity * u64.sizeof);
    m.val    = cast(u64*) xalloc(capacity * u64.sizeof);
    m.used   = cast(u8*) xalloc(capacity);
    memset(m.used, 0, capacity);
    m.base  = base;
    m.mask  = capacity - 1;
    m.count = 0;
}

u64 mapProbe(ByteMap* m, u64 off, u64 len)
{
    u64 h = 2166136261UL;
    for (u64 i = 0; i < len; i++)
    {
        h ^= cast(u64) m.base[off + i];
        h = (h * 16777619UL) & 0xFFFFFFFFUL;
    }

    u64 idx = h & m.mask;
    while (m.used[idx] != 0)
    {
        if (m.keyLen[idx] == len && memcmp(&m.base[m.keyOff[idx]], &m.base[off], cast(size_t) len) == 0)
            return idx;
        idx = (idx + 1) & m.mask;
    }

    return idx;
}

void mapClaim(ByteMap* m, u64 idx, u64 off, u64 len, u64 value)
{
    m.used[idx]   = 1;
    m.keyOff[idx] = off;
    m.keyLen[idx] = len;
    m.val[idx]    = value;
    m.count += 1;
}
