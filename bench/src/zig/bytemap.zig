// Same data, arithmetic and timed region as the other benchmark ports.
const common = @import("common.zig");
const xalloc = common.xalloc;
const memcmp = common.memcmp;
const memset = common.memset;

pub const ByteMap = struct {
    keyOff: [*]u64,
    keyLen: [*]u64,
    val: [*]u64,
    used: [*]u8,
    base: [*]u8,
    mask: u64,
    count: u64,
};
pub fn mapInit(m: *ByteMap, capacity: u64, base: [*]u8) void {
    m.keyOff = @ptrCast(@alignCast(xalloc((capacity * @sizeOf(u64)))));
    m.keyLen = @ptrCast(@alignCast(xalloc((capacity * @sizeOf(u64)))));
    m.val = @ptrCast(@alignCast(xalloc((capacity * @sizeOf(u64)))));
    m.used = @ptrCast(@alignCast(xalloc(capacity)));
    memset(m.used, 0, capacity);
    m.base = base;
    m.mask = (capacity - 1);
    m.count = 0;
}

pub fn mapProbe(m: *ByteMap, off: u64, len: u64) u64 {
    var h: u64 = 2166136261;
    {
        var i: u64 = 0;
        while ((i < len)) : (i += 1) {
            h ^= @as(u64, @intCast(m.base[(off + i)]));
            h = ((h * 16777619) & 0xFFFFFFFF);
        }
    }
    var idx: u64 = (h & m.mask);
    while ((m.used[idx] != 0)) {
        if (((m.keyLen[idx] == len) and (memcmp(&m.base[m.keyOff[idx]], &m.base[off], @as(u64, @intCast(len))) == 0))) {
            return idx;
        }
        idx = ((idx + 1) & m.mask);
    }
    return idx;
}

pub fn mapClaim(m: *ByteMap, idx: u64, off: u64, len: u64, value: u64) void {
    m.used[idx] = 1;
    m.keyOff[idx] = off;
    m.keyLen[idx] = len;
    m.val[idx] = value;
    m.count += 1;
}

