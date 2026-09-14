package main

import common "common"
import bytemap "bytemap"

ROWS :: u64(400000)
REGIONS: [8]cstring = [8]cstring{"EMEA", "APAC", "AMER", "LATAM", "NORDIC", "IBERIA", "BENELUX", "DACH"}
writeUInt :: proc(buf: [^]u8, pos: u64, v: u64) -> u64 {
    tmp: [24]u8
    n: u64 = 0
    x: u64 = v
    if (x == 0) {
        tmp[0] = '0'
        n = 1
    }
    for (x > 0) {
        tmp[n] = u8((48 + (x % 10)))
        n += 1
        x /= 10
    }
    p: u64 = pos
    i: u64 = n
    for (i > 0) {
        i -= 1
        buf[p] = tmp[i]
        p += 1
    }
    return p
}

writeUInt2 :: proc(buf: [^]u8, pos: u64, v: u64) -> u64 {
    buf[pos] = u8((48 + (v / 10)))
    buf[(pos + 1)] = u8((48 + (v % 10)))
    return (pos + 2)
}

main :: proc() {
    text: [^]u8 = ([^]u8)(common.xalloc((ROWS * 48)))
    n: u64 = 0
    for j: u64 = 0; (j < ROWS); j += 1 {
        if (j > 0) {
            text[n] = '\n'
            n += 1
        }
        region := REGIONS[common.rnd() % 8]
        y: u64 = (2024 + (common.rnd() % 3))
        m: u64 = (1 + (common.rnd() % 12))
        d: u64 = (1 + (common.rnd() % 28))
        qty: u64 = (1 + (common.rnd() % 50))
        cents: u64 = (100 + (common.rnd() % 99900))
        n = writeUInt(text, n, j)
        text[n] = ','
        n += 1
        rl: u64 = common.strlen(region)
        for i: u64 = 0; (i < rl); i += 1 {
            text[n] = u8(([^]u8)(region)[i])
            n += 1
        }
        text[n] = ','
        n += 1
        n = writeUInt(text, n, y)
        text[n] = '-'
        n += 1
        n = writeUInt2(text, n, m)
        text[n] = '-'
        n += 1
        n = writeUInt2(text, n, d)
        text[n] = ','
        n += 1
        n = writeUInt(text, n, qty)
        text[n] = ','
        n += 1
        n = writeUInt(text, n, (cents / 100))
        text[n] = '.'
        n += 1
        n = writeUInt2(text, n, (cents % 100))
    }
    t0: f64 = common.now()
    agg: bytemap.ByteMap
    bytemap.mapInit(&agg, 64, text)
    slotCount: [^]u64 = ([^]u64)(common.xalloc((64 * size_of(u64))))
    slotQty: [^]u64 = ([^]u64)(common.xalloc((64 * size_of(u64))))
    slotRev: [^]f64 = ([^]f64)(common.xalloc((64 * size_of(f64))))
    slotMax: [^]f64 = ([^]f64)(common.xalloc((64 * size_of(f64))))
    pos: u64 = 0
    rows: u64 = 0
    for (pos < n) {
        eol: u64 = pos
        for ((eol < n) && (text[eol] != '\n')) {
            eol += 1
        }
        p: u64 = pos
        for ((p < eol) && (text[p] != ',')) {
            p += 1
        }
        p += 1
        rs: u64 = p
        for ((p < eol) && (text[p] != ',')) {
            p += 1
        }
        rlen: u64 = (p - rs)
        p += 1
        for ((p < eol) && (text[p] != ',')) {
            p += 1
        }
        p += 1
        qty: u64 = 0
        for ((p < eol) && (text[p] != ',')) {
            qty = ((qty * 10) + u64((text[p] - 48)))
            p += 1
        }
        p += 1
        ip: u64 = 0
        for ((p < eol) && (text[p] != '.')) {
            ip = ((ip * 10) + u64((text[p] - 48)))
            p += 1
        }
        p += 1
        fr: u64 = 0
        for (p < eol) {
            fr = ((fr * 10) + u64((text[p] - 48)))
            p += 1
        }
        price: f64 = (f64(ip) + (f64(fr) / 100.0))
        idx: u64 = bytemap.mapProbe(&agg, rs, rlen)
        if (agg.used[idx] == 0) {
            slot: u64 = agg.count
            bytemap.mapClaim(&agg, idx, rs, rlen, slot)
            slotCount[slot] = 1
            slotQty[slot] = qty
            slotRev[slot] = (f64(qty) * price)
            slotMax[slot] = price
        } else {
            slot: u64 = agg.val[idx]
            slotCount[slot] += 1
            slotQty[slot] += qty
            slotRev[slot] += (f64(qty) * price)
            if (price > slotMax[slot]) {
                slotMax[slot] = price
            }
        }
        rows += 1
        pos = (eol + 1)
    }
    order: [64]u64
    keyIdx: [64]u64
    nk: u64 = 0
    for i: u64 = 0; (i < 64); i += 1 {
        if (agg.used[i] != 0) {
            keyIdx[nk] = i
            nk += 1
        }
    }
    for i: u64 = 0; (i < nk); i += 1 {
        order[i] = i
    }
    for i: u64 = 0; (i < nk); i += 1 {
        best: u64 = i
        for j: u64 = 0; (j < nk); j += 1 {
            if (j <= i) {
                continue
            }
            a: u64 = keyIdx[order[best]]
            b: u64 = keyIdx[order[j]]
            la: u64 = agg.keyLen[a]
            if (agg.keyLen[b] < la) {
                la = agg.keyLen[b]
            }
            c: i32 = common.memcmp(&text[agg.keyOff[b]], &text[agg.keyOff[a]], u64(la))
            if ((c < 0) || ((c == 0) && (agg.keyLen[b] < agg.keyLen[a]))) {
                best = j
            }
        }
        t: u64 = order[i]
        order[i] = order[best]
        order[best] = t
    }
    check: u64 = rows
    for k: u64 = 0; (k < nk); k += 1 {
        slot: u64 = agg.val[keyIdx[order[k]]]
        check += ((k + 1) * (u64(((slotRev[slot] * 100.0) + 0.5)) % 1000003))
        check += ((slotCount[slot] + slotQty[slot]) + u64(((slotMax[slot] * 100.0) + 0.5)))
    }
    t1: f64 = common.now()
    common.report(check, t0, t1)
    return
}

