package main

import common "common"

N :: u64(800)
NN :: u64((N * N))
INF :: u64(0x0FFFFFFFFFFFFFFF)
g_HeapD: [^]u64
g_HeapN: [^]u64
g_HeapSize: u64 = 0
g_PopD: u64 = 0
g_PopN: u64 = 0
push :: proc(d: u64, node: u64) {
    i: u64 = g_HeapSize
    g_HeapSize += 1
    g_HeapD[i] = d
    g_HeapN[i] = node
    for (i > 0) {
        p: u64 = ((i - 1) >> 1)
        if (g_HeapD[p] <= g_HeapD[i]) {
            break
        }
        td: u64 = g_HeapD[p]
        g_HeapD[p] = g_HeapD[i]
        g_HeapD[i] = td
        tn: u64 = g_HeapN[p]
        g_HeapN[p] = g_HeapN[i]
        g_HeapN[i] = tn
        i = p
    }
}

pop :: proc() {
    g_PopD = g_HeapD[0]
    g_PopN = g_HeapN[0]
    g_HeapSize -= 1
    g_HeapD[0] = g_HeapD[g_HeapSize]
    g_HeapN[0] = g_HeapN[g_HeapSize]
    i: u64 = 0
    for true {
        l: u64 = ((2 * i) + 1)
        if (l >= g_HeapSize) {
            break
        }
        r: u64 = (l + 1)
        m: u64 = l
        if ((r < g_HeapSize) && (g_HeapD[r] < g_HeapD[l])) {
            m = r
        }
        if (g_HeapD[i] <= g_HeapD[m]) {
            break
        }
        td: u64 = g_HeapD[m]
        g_HeapD[m] = g_HeapD[i]
        g_HeapD[i] = td
        tn: u64 = g_HeapN[m]
        g_HeapN[m] = g_HeapN[i]
        g_HeapN[i] = tn
        i = m
    }
}

main :: proc() {
    weight: [^]u64 = ([^]u64)(common.xalloc((NN * size_of(u64))))
    for i: u64 = 0; (i < NN); i += 1 {
        weight[i] = (1 + (common.rnd() % 9))
    }
    // Timed work starts after data generation.
    t0: f64 = common.now()
    dist: [^]u64 = ([^]u64)(common.xalloc((NN * size_of(u64))))
    for i: u64 = 0; (i < NN); i += 1 {
        dist[i] = INF
    }
    g_HeapD = ([^]u64)(common.xalloc(((NN * 4) * size_of(u64))))
    g_HeapN = ([^]u64)(common.xalloc(((NN * 4) * size_of(u64))))
    g_HeapSize = 0
    dist[0] = 0
    push(0, 0)
    pops: u64 = 0
    Target :: u64((NN - 1))
    for (g_HeapSize > 0) {
        pop()
        d: u64 = g_PopD
        u: u64 = g_PopN
        pops += 1
        if (d > dist[u]) {
            continue
        }
        if (u == Target) {
            break
        }
        x: u64 = (u % N)
        y: u64 = (u / N)
        if (x > 0) {
            v: u64 = (u - 1)
            nd: u64 = (d + weight[v])
            if (nd < dist[v]) {
                dist[v] = nd
                push(nd, v)
            }
        }
        if (x < (N - 1)) {
            v: u64 = (u + 1)
            nd: u64 = (d + weight[v])
            if (nd < dist[v]) {
                dist[v] = nd
                push(nd, v)
            }
        }
        if (y > 0) {
            v: u64 = (u - N)
            nd: u64 = (d + weight[v])
            if (nd < dist[v]) {
                dist[v] = nd
                push(nd, v)
            }
        }
        if (y < (N - 1)) {
            v: u64 = (u + N)
            nd: u64 = (d + weight[v])
            if (nd < dist[v]) {
                dist[v] = nd
                push(nd, v)
            }
        }
    }
    check: u64 = ((dist[Target] * 1000) + (pops % 1000))
    t1: f64 = common.now()
    common.report(check, t0, t1)
    common.free(g_HeapN)
    common.free(g_HeapD)
    common.free(dist)
    common.free(weight)
    return
}

