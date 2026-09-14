package bytemap

import common "../common"

ByteMap :: struct {
    keyOff: [^]u64,
    keyLen: [^]u64,
    val: [^]u64,
    used: [^]u8,
    base: [^]u8,
    mask: u64,
    count: u64,
}
mapInit :: proc(m: ^ByteMap, capacity: u64, base: [^]u8) {
    m.keyOff = ([^]u64)(common.xalloc((capacity * size_of(u64))))
    m.keyLen = ([^]u64)(common.xalloc((capacity * size_of(u64))))
    m.val = ([^]u64)(common.xalloc((capacity * size_of(u64))))
    m.used = ([^]u8)(common.xalloc(capacity))
    common.memset(m.used, 0, capacity)
    m.base = base
    m.mask = (capacity - 1)
    m.count = 0
}

mapProbe :: proc(m: ^ByteMap, off: u64, len: u64) -> u64 {
    h: u64 = 2166136261
    for i: u64 = 0; (i < len); i += 1 {
        h ~= u64(m.base[(off + i)])
        h = ((h * 16777619) & 0xFFFFFFFF)
    }
    idx: u64 = (h & m.mask)
    for (m.used[idx] != 0) {
        if ((m.keyLen[idx] == len) && (common.memcmp(&m.base[m.keyOff[idx]], &m.base[off], u64(len)) == 0)) {
            return idx
        }
        idx = ((idx + 1) & m.mask)
    }
    return idx
}

mapClaim :: proc(m: ^ByteMap, idx: u64, off: u64, len: u64, value: u64) {
    m.used[idx] = 1
    m.keyOff[idx] = off
    m.keyLen[idx] = len
    m.val[idx] = value
    m.count += 1
}

