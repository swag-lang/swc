// Same data, arithmetic and timed region as the other benchmark ports.
const common = @import("common.zig");
const rnd = common.rnd;
const now = common.now;
const report = common.report;
const xalloc = common.xalloc;
const free = common.free;

const DATA_SIZE: u64 = 1 << 20;
const WORDS: u64 = 512;
const HASH_SIZE: u64 = 65536;
const WINDOW: i64 = 32768;
const MIN_MATCH: i64 = 4;
const MAX_MATCH: i64 = 258;
const MAX_CHAIN: i64 = 32;

inline fn at(d: [*]const u8, p: i64) u64 {
    return d[@intCast(p)];
}

fn hashAt(d: [*]const u8, p: i64) u64 {
    return (((at(d, p) * 33 + at(d, p + 1)) * 33 + at(d, p + 2)) * 33 + at(d, p + 3)) % HASH_SIZE;
}

pub fn main() void {
    // Data generation is not timed.
    const letters: [*]u8 = @ptrCast(xalloc(WORDS * 10));
    const wordStart: [*]u64 = @ptrCast(@alignCast(xalloc(WORDS * @sizeOf(u64))));
    const wordLen: [*]u64 = @ptrCast(@alignCast(xalloc(WORDS * @sizeOf(u64))));
    var used: u64 = 0;
    {
        var k: u64 = 0;
        while (k < WORDS) : (k += 1) {
            const len: u64 = 2 + rnd() % 8;
            wordStart[k] = used;
            wordLen[k] = len;
            var j: u64 = 0;
            while (j < len) : (j += 1) {
                letters[used + j] = @intCast(97 + rnd() % 26);
            }
            used += len;
        }
    }

    const n: i64 = @intCast(DATA_SIZE);
    const data: [*]u8 = @ptrCast(xalloc(DATA_SIZE));
    {
        var pos: u64 = 0;
        while (pos < DATA_SIZE) {
            const w = rnd() % WORDS;
            var j: u64 = 0;
            while (j < wordLen[w] and pos < DATA_SIZE) : (j += 1) {
                data[pos] = letters[wordStart[w] + j];
                pos += 1;
            }
            if (pos < DATA_SIZE) {
                data[pos] = ' ';
                pos += 1;
            }
        }
    }

    // Timed work starts after data generation.
    const t0: f64 = now();

    const head: [*]i64 = @ptrCast(@alignCast(xalloc(HASH_SIZE * @sizeOf(i64))));
    const prev: [*]i64 = @ptrCast(@alignCast(xalloc(@as(u64, @intCast(WINDOW)) * @sizeOf(i64))));
    {
        var k: u64 = 0;
        while (k < HASH_SIZE) : (k += 1) head[k] = -1;
        k = 0;
        while (k < WINDOW) : (k += 1) prev[k] = -1;
    }

    const comp: [*]u8 = @ptrCast(xalloc(DATA_SIZE * 2 + 16));
    var csize: u64 = 0;

    var i: i64 = 0;
    while (i + MIN_MATCH <= n) {
        var best: i64 = 0;
        var dist: i64 = 0;
        const limit: i64 = if (n - i < MAX_MATCH) n - i else MAX_MATCH;
        const h = hashAt(data, i);
        var cand: i64 = head[h];
        var chain: i64 = 0;
        while (cand >= 0 and i - cand < WINDOW and chain < MAX_CHAIN) : (chain += 1) {
            var l: i64 = 0;
            while (l < limit and data[@intCast(cand + l)] == data[@intCast(i + l)]) l += 1;
            if (l > best) {
                best = l;
                dist = i - cand;
                if (l == limit) break;
            }
            cand = prev[@intCast(@mod(cand, WINDOW))];
        }

        prev[@intCast(@mod(i, WINDOW))] = head[h];
        head[h] = i;

        if (best >= MIN_MATCH) {
            comp[csize] = 1;
            comp[csize + 1] = @intCast(best - MIN_MATCH);
            comp[csize + 2] = @intCast(@mod(dist - 1, 256));
            comp[csize + 3] = @intCast(@divTrunc(dist - 1, 256));
            csize += 4;
            var p: i64 = i + 1;
            while (p < i + best) : (p += 1) {
                if (p + MIN_MATCH <= n) {
                    const hp = hashAt(data, p);
                    prev[@intCast(@mod(p, WINDOW))] = head[hp];
                    head[hp] = p;
                }
            }
            i += best;
        } else {
            comp[csize] = 0;
            comp[csize + 1] = data[@intCast(i)];
            csize += 2;
            i += 1;
        }
    }

    while (i < n) : (i += 1) {
        comp[csize] = 0;
        comp[csize + 1] = data[@intCast(i)];
        csize += 2;
    }

    // Decompress and verify.
    const out: [*]u8 = @ptrCast(xalloc(DATA_SIZE));
    var o: u64 = 0;
    var c: u64 = 0;
    while (c < csize) {
        if (comp[c] == 0) {
            out[o] = comp[c + 1];
            o += 1;
            c += 2;
        } else {
            const len: u64 = @as(u64, comp[c + 1]) + MIN_MATCH;
            const back: u64 = @as(u64, comp[c + 2]) + @as(u64, comp[c + 3]) * 256 + 1;
            var k: u64 = 0;
            while (k < len) : (k += 1) {
                out[o] = out[o - back];
                o += 1;
            }
            c += 4;
        }
    }

    var same = o == DATA_SIZE;
    {
        var k: u64 = 0;
        while (same and k < DATA_SIZE) : (k += 1) {
            if (out[k] != data[k]) same = false;
        }
    }

    var hc: u64 = 0;
    {
        var k: u64 = 0;
        while (k < csize) : (k += 1) hc = (hc * 31 + comp[k]) % 1000003;
    }

    const check: u64 = if (same) csize * 1000003 + hc else 0;

    const t1: f64 = now();
    report(check, t0, t1);

    free(out);
    free(comp);
    free(prev);
    free(head);
    free(data);
    free(wordLen);
    free(wordStart);
    free(letters);
}
