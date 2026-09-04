const N   = 800'u64
const NN  = N * N
const INF = 0x0FFFFFFFFFFFFFFF'u64

var g_HeapD: [*] u64
var g_HeapN: [*] u64
var g_HeapSize       = 0'u64

var g_PopD = 0'u64
var g_PopN = 0'u64

func push(d, node: u64)
{
    var i = g_HeapSize
    g_HeapSize += 1
    g_HeapD[i] = d
    g_HeapN[i] = node

    while i > 0
    {
        let p = (i - 1) >> 1
        if g_HeapD[p] <= g_HeapD[i] do
            break
        let td = g_HeapD[p]
        g_HeapD[p] = g_HeapD[i]
        g_HeapD[i] = td
        let tn = g_HeapN[p]
        g_HeapN[p] = g_HeapN[i]
        g_HeapN[i] = tn
        i = p
    }
}

func pop()
{
    g_PopD = g_HeapD[0]
    g_PopN = g_HeapN[0]
    g_HeapSize -= 1
    g_HeapD[0] = g_HeapD[g_HeapSize]
    g_HeapN[0] = g_HeapN[g_HeapSize]

    var i = 0'u64
    while true
    {
        let l = 2 * i + 1
        if l >= g_HeapSize do
            break
        let r = l + 1
        var m = l
        if r < g_HeapSize and g_HeapD[r] < g_HeapD[l] do
            m = r
        if g_HeapD[i] <= g_HeapD[m] do
            break
        let td = g_HeapD[m]
        g_HeapD[m] = g_HeapD[i]
        g_HeapD[i] = td
        let tn = g_HeapN[m]
        g_HeapN[m] = g_HeapN[i]
        g_HeapN[i] = tn
        i = m
    }
}

#main
{
    // ---- data generation (not timed) ----
    let weight = cast([*] u64) (benchAlloc(NN * #sizeof(u64)))!
    for i in NN do
        weight[i] = 1 + (rnd() % 9)

    // ---- timed work ----
    let t0 = now()

    let dist = cast([*] u64) (benchAlloc(NN * #sizeof(u64)))!
    for i in NN do
        dist[i] = INF

    g_HeapD    = cast([*] u64) (benchAlloc(NN * 4 * #sizeof(u64)))!
    g_HeapN    = cast([*] u64) (benchAlloc(NN * 4 * #sizeof(u64)))!
    g_HeapSize = 0

    dist[0] = 0
    push(0, 0)

    var pops         = 0'u64
    const Target     = NN - 1

    while g_HeapSize > 0
    {
        pop()
        let d = g_PopD
        let u = g_PopN
        pops += 1
        if d > dist[u] do
            continue
        if u == Target do
            break

        let x = u % N
        let y = u / N

        if x > 0
        {
            let v  = u - 1
            let nd = d + weight[v]
            if nd < dist[v]
            {
                dist[v] = nd
                push(nd, v)
            }
        }
        if x < N - 1
        {
            let v  = u + 1
            let nd = d + weight[v]
            if nd < dist[v]
            {
                dist[v] = nd
                push(nd, v)
            }
        }
        if y > 0
        {
            let v  = u - N
            let nd = d + weight[v]
            if nd < dist[v]
            {
                dist[v] = nd
                push(nd, v)
            }
        }
        if y < N - 1
        {
            let v  = u + N
            let nd = d + weight[v]
            if nd < dist[v]
            {
                dist[v] = nd
                push(nd, v)
            }
        }
    }

    let check = dist[Target] * 1000 + (pops % 1000)

    let t1 = now()
    report(check, t0, t1)

    benchFree(g_HeapN)
    benchFree(g_HeapD)
    benchFree(dist)
    benchFree(weight)
}
