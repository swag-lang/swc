package main

import common "common"

DICT :: u64(6000)
QUERIES :: u64(40)
MAXLEN :: u64(3)
g_Bytes: [^]u8
g_WordOff: [^]u64
g_WordLen: [^]u64
g_QBytes: [^]u8
g_QOff: [^]u64
g_QLen: [^]u64
main :: proc() {
    g_Bytes = ([^]u8)(common.xalloc((DICT * 16)))
    g_WordOff = ([^]u64)(common.xalloc((DICT * size_of(u64))))
    g_WordLen = ([^]u64)(common.xalloc((DICT * size_of(u64))))
    wp: u64 = 0
    for i: u64 = 0; (i < DICT); i += 1 {
        n: u64 = (i + 1)
        l: u64 = (4 + (i % 7))
        g_WordOff[i] = wp
        g_WordLen[i] = l
        for k: u64 = 0; (k < l); k += 1 {
            g_Bytes[wp] = u8((97 + (n % 26)))
            wp += 1
            n = ((n / 26) + (7 * k))
        }
    }
    g_QBytes = ([^]u8)(common.xalloc((QUERIES * 32)))
    g_QOff = ([^]u64)(common.xalloc((QUERIES * size_of(u64))))
    g_QLen = ([^]u64)(common.xalloc((QUERIES * size_of(u64))))
    qp: u64 = 0
    for q: u64 = 0; (q < QUERIES); q += 1 {
        tmp: [32]u8
        src: u64 = (common.rnd() % DICT)
        nw: u64 = g_WordLen[src]
        for i: u64 = 0; (i < nw); i += 1 {
            tmp[i] = g_Bytes[(g_WordOff[src] + i)]
        }
        for rep: u64 = 0; (rep < 2); rep += 1 {
            p: u64 = (common.rnd() % nw)
            op: u64 = (common.rnd() % 3)
            c: u8 = u8((97 + (common.rnd() % 26)))
            if (op == 0) {
                tmp[p] = c
            } else {
                if (op == 1) {
                    if (nw > 2) {
                        i: u64 = p
                        for ((i + 1) < nw) {
                            tmp[i] = tmp[(i + 1)]
                            i += 1
                        }
                        nw -= 1
                    }
                } else {
                    i: u64 = nw
                    for (i > p) {
                        tmp[i] = tmp[(i - 1)]
                        i -= 1
                    }
                    tmp[p] = c
                    nw += 1
                }
            }
        }
        g_QOff[q] = qp
        g_QLen[q] = nw
        for i: u64 = 0; (i < nw); i += 1 {
            g_QBytes[qp] = tmp[i]
            qp += 1
        }
    }
    t0: f64 = common.now()
    row0: [64]u64
    row1: [64]u64
    check: i64 = 0
    for q: u64 = 0; (q < QUERIES); q += 1 {
        ao: u64 = g_QOff[q]
        la: u64 = g_QLen[q]
        best: u64 = 1073741824
        bestIdx: i64 = -1
        for i: u64 = 0; (i < DICT); i += 1 {
            bo: u64 = g_WordOff[i]
            lb: u64 = g_WordLen[i]
            d: u64 = 0
            if (la > lb) {
                d = (la - lb)
            } else {
                d = (lb - la)
            }
            if (d > MAXLEN) {
                continue
            }
            for j: u64 = 0; (j < (lb + 1)); j += 1 {
                row0[j] = j
            }
            for x: u64 = 0; (x < la); x += 1 {
                row1[0] = (x + 1)
                ca: u8 = g_QBytes[(ao + x)]
                for y: u64 = 0; (y < lb); y += 1 {
                    cost: u64 = 1
                    if (ca == g_Bytes[(bo + y)]) {
                        cost = 0
                    }
                    v: u64 = (row0[y] + cost)
                    v2: u64 = (row0[(y + 1)] + 1)
                    if (v2 < v) {
                        v = v2
                    }
                    v2 = (row1[y] + 1)
                    if (v2 < v) {
                        v = v2
                    }
                    row1[(y + 1)] = v
                }
                for j: u64 = 0; (j < (lb + 1)); j += 1 {
                    row0[j] = row1[j]
                }
            }
            dd: u64 = row0[lb]
            if (dd < best) {
                best = dd
                bestIdx = i64(i)
            }
        }
        check += ((i64(best) * 31) + bestIdx)
    }
    t1: f64 = common.now()
    common.report(u64(check), t0, t1)
    return
}

