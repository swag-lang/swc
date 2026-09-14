// Same data, arithmetic and timed region as the other benchmark ports.
const common = @import("common.zig");
const rnd = common.rnd;
const now = common.now;
const report = common.report;
const xalloc = common.xalloc;

const DICT: u64 = 6000;
const QUERIES: u64 = 40;
const MAXLEN: u64 = 3;
var g_Bytes: [*]u8 = undefined;
var g_WordOff: [*]u64 = undefined;
var g_WordLen: [*]u64 = undefined;
var g_QBytes: [*]u8 = undefined;
var g_QOff: [*]u64 = undefined;
var g_QLen: [*]u64 = undefined;
pub fn main() void {
    g_Bytes = @ptrCast(@alignCast(xalloc((DICT * 16))));
    g_WordOff = @ptrCast(@alignCast(xalloc((DICT * @sizeOf(u64)))));
    g_WordLen = @ptrCast(@alignCast(xalloc((DICT * @sizeOf(u64)))));
    var wp: u64 = 0;
    {
        var i: u64 = 0;
        while ((i < DICT)) : (i += 1) {
            var n: u64 = (i + 1);
            const l: u64 = (4 + (i % 7));
            g_WordOff[i] = wp;
            g_WordLen[i] = l;
            {
                var k: u64 = 0;
                while ((k < l)) : (k += 1) {
                    g_Bytes[wp] = @as(u8, @intCast((97 + (n % 26))));
                    wp += 1;
                    n = ((n / 26) + (7 * k));
                }
            }
        }
    }
    g_QBytes = @ptrCast(@alignCast(xalloc((QUERIES * 32))));
    g_QOff = @ptrCast(@alignCast(xalloc((QUERIES * @sizeOf(u64)))));
    g_QLen = @ptrCast(@alignCast(xalloc((QUERIES * @sizeOf(u64)))));
    var qp: u64 = 0;
    {
        var q: u64 = 0;
        while ((q < QUERIES)) : (q += 1) {
            var tmp: [32]u8 = undefined;
            const src: u64 = (rnd() % DICT);
            var nw: u64 = g_WordLen[src];
            {
                var i: u64 = 0;
                while ((i < nw)) : (i += 1) {
                    tmp[i] = g_Bytes[(g_WordOff[src] + i)];
                }
            }
            {
                var rep: u64 = 0;
                while ((rep < 2)) : (rep += 1) {
                    const p: u64 = (rnd() % nw);
                    const op: u64 = (rnd() % 3);
                    const c: u8 = @as(u8, @intCast((97 + (rnd() % 26))));
                    if ((op == 0)) {
                        tmp[p] = c;
                    } else {
                        if ((op == 1)) {
                            if ((nw > 2)) {
                                var i: u64 = p;
                                while (((i + 1) < nw)) {
                                    tmp[i] = tmp[(i + 1)];
                                    i += 1;
                                }
                                nw -= 1;
                            }
                        } else {
                            var i: u64 = nw;
                            while ((i > p)) {
                                tmp[i] = tmp[(i - 1)];
                                i -= 1;
                            }
                            tmp[p] = c;
                            nw += 1;
                        }
                    }
                }
            }
            g_QOff[q] = qp;
            g_QLen[q] = nw;
            {
                var i: u64 = 0;
                while ((i < nw)) : (i += 1) {
                    g_QBytes[qp] = tmp[i];
                    qp += 1;
                }
            }
        }
    }
    const t0: f64 = now();
    var row0: [64]u64 = undefined;
    var row1: [64]u64 = undefined;
    var check: i64 = 0;
    {
        var q: u64 = 0;
        while ((q < QUERIES)) : (q += 1) {
            const ao: u64 = g_QOff[q];
            const la: u64 = g_QLen[q];
            var best: u64 = 1073741824;
            var bestIdx: i64 = -1;
            {
                var i: u64 = 0;
                while ((i < DICT)) : (i += 1) {
                    const bo: u64 = g_WordOff[i];
                    const lb: u64 = g_WordLen[i];
                    var d: u64 = 0;
                    if ((la > lb)) {
                        d = (la - lb);
                    } else {
                        d = (lb - la);
                    }
                    if ((d > MAXLEN)) {
                        continue;
                    }
                    {
                        var j: u64 = 0;
                        while ((j < (lb + 1))) : (j += 1) {
                            row0[j] = j;
                        }
                    }
                    {
                        var x: u64 = 0;
                        while ((x < la)) : (x += 1) {
                            row1[0] = (x + 1);
                            const ca: u8 = g_QBytes[(ao + x)];
                            {
                                var y: u64 = 0;
                                while ((y < lb)) : (y += 1) {
                                    var cost: u64 = 1;
                                    if ((ca == g_Bytes[(bo + y)])) {
                                        cost = 0;
                                    }
                                    var v: u64 = (row0[y] + cost);
                                    var v2: u64 = (row0[(y + 1)] + 1);
                                    if ((v2 < v)) {
                                        v = v2;
                                    }
                                    v2 = (row1[y] + 1);
                                    if ((v2 < v)) {
                                        v = v2;
                                    }
                                    row1[(y + 1)] = v;
                                }
                            }
                            {
                                var j: u64 = 0;
                                while ((j < (lb + 1))) : (j += 1) {
                                    row0[j] = row1[j];
                                }
                            }
                        }
                    }
                    const dd: u64 = row0[lb];
                    if ((dd < best)) {
                        best = dd;
                        bestIdx = @as(i64, @intCast(i));
                    }
                }
            }
            check += ((@as(i64, @intCast(best)) * 31) + bestIdx);
        }
    }
    const t1: f64 = now();
    report(@as(u64, @intCast(check)), t0, t1);
    return;
}

