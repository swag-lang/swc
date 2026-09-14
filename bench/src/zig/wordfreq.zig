// Same data, arithmetic and timed region as the other benchmark ports.
const common = @import("common.zig");
const rnd = common.rnd;
const now = common.now;
const report = common.report;
const xalloc = common.xalloc;
const memcmp = common.memcmp;
const bytemap = @import("bytemap.zig");
const ByteMap = bytemap.ByteMap;
const mapInit = bytemap.mapInit;
const mapProbe = bytemap.mapProbe;
const mapClaim = bytemap.mapClaim;

const VOCAB: u64 = 5000;
const WORDS: u64 = 2000000;
const CAP: u64 = 16384;
var g_Text: [*]u8 = undefined;
var g_Cnt: [*]u64 = undefined;
var g_Off: [*]u64 = undefined;
var g_Len: [*]u64 = undefined;
var g_Idx: [*]u64 = undefined;
fn less(a: u64, b: u64) bool {
    if ((g_Cnt[a] != g_Cnt[b])) {
        return (g_Cnt[a] > g_Cnt[b]);
    }
    var n: u64 = g_Len[a];
    if ((g_Len[b] < n)) {
        n = g_Len[b];
    }
    const c: i32 = memcmp(&g_Text[g_Off[a]], &g_Text[g_Off[b]], @as(u64, @intCast(n)));
    if ((c != 0)) {
        return (c < 0);
    }
    return (g_Len[a] < g_Len[b]);
}

fn qsortIdx(lowIn: i64, highIn: i64) void {
    var low: i64 = lowIn;
    const high: i64 = highIn;
    while ((low < high)) {
        const p: u64 = g_Idx[@as(u64, @intCast(@divTrunc((low + high), 2)))];
        var i: i64 = low;
        var j: i64 = high;
        while ((i <= j)) {
            while (less(g_Idx[@as(u64, @intCast(i))], p)) {
                i += 1;
            }
            while (less(p, g_Idx[@as(u64, @intCast(j))])) {
                j -= 1;
            }
            if ((i <= j)) {
                const t: u64 = g_Idx[@as(u64, @intCast(i))];
                g_Idx[@as(u64, @intCast(i))] = g_Idx[@as(u64, @intCast(j))];
                g_Idx[@as(u64, @intCast(j))] = t;
                i += 1;
                j -= 1;
            }
        }
        qsortIdx(low, j);
        low = i;
    }
}

pub fn main() void {
    const vocabBytes: [*]u8 = @ptrCast(@alignCast(xalloc((VOCAB * 16))));
    const vocabOff: [*]u64 = @ptrCast(@alignCast(xalloc((VOCAB * @sizeOf(u64)))));
    const vocabLen: [*]u64 = @ptrCast(@alignCast(xalloc((VOCAB * @sizeOf(u64)))));
    var vp: u64 = 0;
    {
        var i: u64 = 0;
        while ((i < VOCAB)) : (i += 1) {
            var nn: u64 = (i + 1);
            const l: u64 = (3 + (i % 6));
            vocabOff[i] = vp;
            vocabLen[i] = l;
            {
                var k: u64 = 0;
                while ((k < l)) : (k += 1) {
                    vocabBytes[vp] = @as(u8, @intCast((97 + (nn % 26))));
                    vp += 1;
                    nn = ((nn / 26) + (7 * k));
                }
            }
        }
    }
    g_Text = @ptrCast(@alignCast(xalloc((WORDS * 12))));
    var n: u64 = 0;
    {
        var j: u64 = 0;
        while ((j < WORDS)) : (j += 1) {
            const idx: u64 = (rnd() % VOCAB);
            const o: u64 = vocabOff[idx];
            const l: u64 = vocabLen[idx];
            {
                var k: u64 = 0;
                while ((k < l)) : (k += 1) {
                    g_Text[n] = vocabBytes[(o + k)];
                    n += 1;
                }
            }
            if ((((j + 1) % 12) == 0)) {
                g_Text[n] = '\n';
            } else {
                g_Text[n] = ' ';
            }
            n += 1;
        }
    }
    const t0: f64 = now();
    var counts: ByteMap = undefined;
    mapInit(&counts, CAP, g_Text);
    var start: u64 = 0;
    var open: bool = false;
    var i: u64 = 0;
    while ((i < n)) {
        const c: u8 = g_Text[i];
        if (((c >= 97) and (c <= 122))) {
            if (!open) {
                start = i;
                open = true;
            }
        } else {
            if (open) {
                const idx: u64 = mapProbe(&counts, start, (i - start));
                if ((counts.used[idx] == 0)) {
                    mapClaim(&counts, idx, start, (i - start), 1);
                } else {
                    counts.val[idx] += 1;
                }
                open = false;
            }
        }
        i += 1;
    }
    if (open) {
        const idx: u64 = mapProbe(&counts, start, (n - start));
        if ((counts.used[idx] == 0)) {
            mapClaim(&counts, idx, start, (n - start), 1);
        } else {
            counts.val[idx] += 1;
        }
    }
    const distinct: u64 = counts.count;
    g_Cnt = @ptrCast(@alignCast(xalloc((distinct * @sizeOf(u64)))));
    g_Off = @ptrCast(@alignCast(xalloc((distinct * @sizeOf(u64)))));
    g_Len = @ptrCast(@alignCast(xalloc((distinct * @sizeOf(u64)))));
    g_Idx = @ptrCast(@alignCast(xalloc((distinct * @sizeOf(u64)))));
    var ni: u64 = 0;
    {
        var s: u64 = 0;
        while ((s < CAP)) : (s += 1) {
            if ((counts.used[s] == 0)) {
                continue;
            }
            g_Cnt[ni] = counts.val[s];
            g_Off[ni] = counts.keyOff[s];
            g_Len[ni] = counts.keyLen[s];
            g_Idx[ni] = ni;
            ni += 1;
        }
    }
    qsortIdx(0, (@as(i64, @intCast(distinct)) - 1));
    var check: u64 = (distinct * 7);
    {
        var k: u64 = 0;
        while ((k < 20)) : (k += 1) {
            check += ((k + 1) * g_Cnt[g_Idx[k]]);
        }
    }
    const t1: f64 = now();
    report(check, t0, t1);
    return;
}

