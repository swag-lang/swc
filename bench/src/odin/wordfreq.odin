package main

import common "common"
import bytemap "bytemap"

VOCAB :: u64(5000)
WORDS :: u64(2000000)
CAP :: u64(16384)
g_Text: [^]u8
g_Cnt: [^]u64
g_Off: [^]u64
g_Len: [^]u64
g_Idx: [^]u64
less :: proc(a: u64, b: u64) -> bool {
    if (g_Cnt[a] != g_Cnt[b]) {
        return (g_Cnt[a] > g_Cnt[b])
    }
    n: u64 = g_Len[a]
    if (g_Len[b] < n) {
        n = g_Len[b]
    }
    c: i32 = common.memcmp(&g_Text[g_Off[a]], &g_Text[g_Off[b]], u64(n))
    if (c != 0) {
        return (c < 0)
    }
    return (g_Len[a] < g_Len[b])
}

qsortIdx :: proc(lowIn: i64, highIn: i64) {
    low: i64 = lowIn
    high: i64 = highIn
    for (low < high) {
        p: u64 = g_Idx[u64(((low + high) / 2))]
        i: i64 = low
        j: i64 = high
        for (i <= j) {
            for less(g_Idx[u64(i)], p) {
                i += 1
            }
            for less(p, g_Idx[u64(j)]) {
                j -= 1
            }
            if (i <= j) {
                t: u64 = g_Idx[u64(i)]
                g_Idx[u64(i)] = g_Idx[u64(j)]
                g_Idx[u64(j)] = t
                i += 1
                j -= 1
            }
        }
        qsortIdx(low, j)
        low = i
    }
}

main :: proc() {
    vocabBytes: [^]u8 = ([^]u8)(common.xalloc((VOCAB * 16)))
    vocabOff: [^]u64 = ([^]u64)(common.xalloc((VOCAB * size_of(u64))))
    vocabLen: [^]u64 = ([^]u64)(common.xalloc((VOCAB * size_of(u64))))
    vp: u64 = 0
    for i: u64 = 0; (i < VOCAB); i += 1 {
        nn: u64 = (i + 1)
        l: u64 = (3 + (i % 6))
        vocabOff[i] = vp
        vocabLen[i] = l
        for k: u64 = 0; (k < l); k += 1 {
            vocabBytes[vp] = u8((97 + (nn % 26)))
            vp += 1
            nn = ((nn / 26) + (7 * k))
        }
    }
    g_Text = ([^]u8)(common.xalloc((WORDS * 12)))
    n: u64 = 0
    for j: u64 = 0; (j < WORDS); j += 1 {
        idx: u64 = (common.rnd() % VOCAB)
        o: u64 = vocabOff[idx]
        l: u64 = vocabLen[idx]
        for k: u64 = 0; (k < l); k += 1 {
            g_Text[n] = vocabBytes[(o + k)]
            n += 1
        }
        if (((j + 1) % 12) == 0) {
            g_Text[n] = '\n'
        } else {
            g_Text[n] = ' '
        }
        n += 1
    }
    t0: f64 = common.now()
    counts: bytemap.ByteMap
    bytemap.mapInit(&counts, CAP, g_Text)
    start: u64 = 0
    open: bool = false
    i: u64 = 0
    for (i < n) {
        c: u8 = g_Text[i]
        if ((c >= 97) && (c <= 122)) {
            if !open {
                start = i
                open = true
            }
        } else {
            if open {
                idx: u64 = bytemap.mapProbe(&counts, start, (i - start))
                if (counts.used[idx] == 0) {
                    bytemap.mapClaim(&counts, idx, start, (i - start), 1)
                } else {
                    counts.val[idx] += 1
                }
                open = false
            }
        }
        i += 1
    }
    if open {
        idx: u64 = bytemap.mapProbe(&counts, start, (n - start))
        if (counts.used[idx] == 0) {
            bytemap.mapClaim(&counts, idx, start, (n - start), 1)
        } else {
            counts.val[idx] += 1
        }
    }
    distinctCount: u64 = counts.count
    g_Cnt = ([^]u64)(common.xalloc((distinctCount * size_of(u64))))
    g_Off = ([^]u64)(common.xalloc((distinctCount * size_of(u64))))
    g_Len = ([^]u64)(common.xalloc((distinctCount * size_of(u64))))
    g_Idx = ([^]u64)(common.xalloc((distinctCount * size_of(u64))))
    ni: u64 = 0
    for s: u64 = 0; (s < CAP); s += 1 {
        if (counts.used[s] == 0) {
            continue
        }
        g_Cnt[ni] = counts.val[s]
        g_Off[ni] = counts.keyOff[s]
        g_Len[ni] = counts.keyLen[s]
        g_Idx[ni] = ni
        ni += 1
    }
    qsortIdx(0, (i64(distinctCount) - 1))
    check: u64 = (distinctCount * 7)
    for k: u64 = 0; (k < 20); k += 1 {
        check += ((k + 1) * g_Cnt[g_Idx[k]])
    }
    t1: f64 = common.now()
    common.report(check, t0, t1)
    return
}

