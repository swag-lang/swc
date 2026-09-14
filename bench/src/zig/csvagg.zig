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

const ROWS: u64 = 400000;
const REGIONS: [8][:0]const u8 = [8][:0]const u8{"EMEA", "APAC", "AMER", "LATAM", "NORDIC", "IBERIA", "BENELUX", "DACH"};
fn writeUInt(buf: [*]u8, pos: u64, v: u64) u64 {
    var tmp: [24]u8 = undefined;
    var n: u64 = 0;
    var x: u64 = v;
    if ((x == 0)) {
        tmp[0] = '0';
        n = 1;
    }
    while ((x > 0)) {
        tmp[n] = @as(u8, @intCast((48 + (x % 10))));
        n += 1;
        x /= 10;
    }
    var p: u64 = pos;
    var i: u64 = n;
    while ((i > 0)) {
        i -= 1;
        buf[p] = tmp[i];
        p += 1;
    }
    return p;
}

fn writeUInt2(buf: [*]u8, pos: u64, v: u64) u64 {
    buf[pos] = @as(u8, @intCast((48 + (v / 10))));
    buf[(pos + 1)] = @as(u8, @intCast((48 + (v % 10))));
    return (pos + 2);
}

pub fn main() void {
    const text: [*]u8 = @ptrCast(@alignCast(xalloc((ROWS * 48))));
    var n: u64 = 0;
    {
        var j: u64 = 0;
        while ((j < ROWS)) : (j += 1) {
            if ((j > 0)) {
                text[n] = '\n';
                n += 1;
            }
            const region: [:0]const u8 = REGIONS[(rnd() % 8)];
            const y: u64 = (2024 + (rnd() % 3));
            const m: u64 = (1 + (rnd() % 12));
            const d: u64 = (1 + (rnd() % 28));
            const qty: u64 = (1 + (rnd() % 50));
            const cents: u64 = (100 + (rnd() % 99900));
            n = writeUInt(text, n, j);
            text[n] = ',';
            n += 1;
            const rl: u64 = region.len;
            {
                var i: u64 = 0;
                while ((i < rl)) : (i += 1) {
                    text[n] = @as(u8, @intCast(region[i]));
                    n += 1;
                }
            }
            text[n] = ',';
            n += 1;
            n = writeUInt(text, n, y);
            text[n] = '-';
            n += 1;
            n = writeUInt2(text, n, m);
            text[n] = '-';
            n += 1;
            n = writeUInt2(text, n, d);
            text[n] = ',';
            n += 1;
            n = writeUInt(text, n, qty);
            text[n] = ',';
            n += 1;
            n = writeUInt(text, n, (cents / 100));
            text[n] = '.';
            n += 1;
            n = writeUInt2(text, n, (cents % 100));
        }
    }
    // Timed work starts after data generation.
    const t0: f64 = now();
    var agg: ByteMap = undefined;
    mapInit(&agg, 64, text);
    const slotCount: [*]u64 = @ptrCast(@alignCast(xalloc((64 * @sizeOf(u64)))));
    const slotQty: [*]u64 = @ptrCast(@alignCast(xalloc((64 * @sizeOf(u64)))));
    const slotRev: [*]f64 = @ptrCast(@alignCast(xalloc((64 * @sizeOf(f64)))));
    const slotMax: [*]f64 = @ptrCast(@alignCast(xalloc((64 * @sizeOf(f64)))));
    var pos: u64 = 0;
    var rows: u64 = 0;
    while ((pos < n)) {
        var eol: u64 = pos;
        while (((eol < n) and (text[eol] != '\n'))) {
            eol += 1;
        }
        var p: u64 = pos;
        while (((p < eol) and (text[p] != ','))) {
            p += 1;
        }
        p += 1;
        const rs: u64 = p;
        while (((p < eol) and (text[p] != ','))) {
            p += 1;
        }
        const rlen: u64 = (p - rs);
        p += 1;
        while (((p < eol) and (text[p] != ','))) {
            p += 1;
        }
        p += 1;
        var qty: u64 = 0;
        while (((p < eol) and (text[p] != ','))) {
            qty = ((qty * 10) + @as(u64, @intCast((text[p] - 48))));
            p += 1;
        }
        p += 1;
        var ip: u64 = 0;
        while (((p < eol) and (text[p] != '.'))) {
            ip = ((ip * 10) + @as(u64, @intCast((text[p] - 48))));
            p += 1;
        }
        p += 1;
        var fr: u64 = 0;
        while ((p < eol)) {
            fr = ((fr * 10) + @as(u64, @intCast((text[p] - 48))));
            p += 1;
        }
        const price: f64 = (@as(f64, @floatFromInt(ip)) + (@as(f64, @floatFromInt(fr)) / 100.0));
        const idx: u64 = mapProbe(&agg, rs, rlen);
        if ((agg.used[idx] == 0)) {
            const slot: u64 = agg.count;
            mapClaim(&agg, idx, rs, rlen, slot);
            slotCount[slot] = 1;
            slotQty[slot] = qty;
            slotRev[slot] = (@as(f64, @floatFromInt(qty)) * price);
            slotMax[slot] = price;
        } else {
            const slot: u64 = agg.val[idx];
            slotCount[slot] += 1;
            slotQty[slot] += qty;
            slotRev[slot] += (@as(f64, @floatFromInt(qty)) * price);
            if ((price > slotMax[slot])) {
                slotMax[slot] = price;
            }
        }
        rows += 1;
        pos = (eol + 1);
    }
    var order: [64]u64 = undefined;
    var keyIdx: [64]u64 = undefined;
    var nk: u64 = 0;
    {
        var i: u64 = 0;
        while ((i < 64)) : (i += 1) {
            if ((agg.used[i] != 0)) {
                keyIdx[nk] = i;
                nk += 1;
            }
        }
    }
    {
        var i: u64 = 0;
        while ((i < nk)) : (i += 1) {
            order[i] = i;
        }
    }
    {
        var i: u64 = 0;
        while ((i < nk)) : (i += 1) {
            var best: u64 = i;
            {
                var j: u64 = 0;
                while ((j < nk)) : (j += 1) {
                    if ((j <= i)) {
                        continue;
                    }
                    const a: u64 = keyIdx[order[best]];
                    const b: u64 = keyIdx[order[j]];
                    var la: u64 = agg.keyLen[a];
                    if ((agg.keyLen[b] < la)) {
                        la = agg.keyLen[b];
                    }
                    const c: i32 = memcmp(&text[agg.keyOff[b]], &text[agg.keyOff[a]], @as(u64, @intCast(la)));
                    if (((c < 0) or ((c == 0) and (agg.keyLen[b] < agg.keyLen[a])))) {
                        best = j;
                    }
                }
            }
            const t: u64 = order[i];
            order[i] = order[best];
            order[best] = t;
        }
    }
    var check: u64 = rows;
    {
        var k: u64 = 0;
        while ((k < nk)) : (k += 1) {
            const slot: u64 = agg.val[keyIdx[order[k]]];
            check += ((k + 1) * (@as(u64, @intFromFloat(((slotRev[slot] * 100.0) + 0.5))) % 1000003));
            check += ((slotCount[slot] + slotQty[slot]) + @as(u64, @intFromFloat(((slotMax[slot] * 100.0) + 0.5))));
        }
    }
    const t1: f64 = now();
    report(check, t0, t1);
    return;
}

