const DICT    = 6000'u64
const QUERIES = 40'u64
const MAXLEN  = 3'u64

var g_Bytes:  [*] u8  = undefined
var g_WordOff: [*] u64 = undefined
var g_WordLen: [*] u64 = undefined

var g_QBytes:  [*] u8  = undefined
var g_QOff:    [*] u64 = undefined
var g_QLen:    [*] u64 = undefined

#run
{
    // ---- data generation (not timed) ----
    g_Bytes   = cast([*] u8) (@alloc(DICT * 16))!
    g_WordOff = cast([*] u64) (@alloc(DICT * #sizeof(u64)))!
    g_WordLen = cast([*] u64) (@alloc(DICT * #sizeof(u64)))!

    var wp = 0'u64
    for [i] in DICT
    {
        var n = i + 1
        let l = 4 + (i % 7)
        g_WordOff[i] = wp
        g_WordLen[i] = l
        for [k] in l
        {
            g_Bytes[wp] = cast(u8)(97 + (n % 26))
            wp += 1
            n = n / 26 + 7 * k
        }
    }

    g_QBytes = cast([*] u8) (@alloc(QUERIES * 32))!
    g_QOff   = cast([*] u64) (@alloc(QUERIES * #sizeof(u64)))!
    g_QLen   = cast([*] u64) (@alloc(QUERIES * #sizeof(u64)))!

    var qp = 0'u64
    for [q] in QUERIES
    {
        var tmp: [32] u8 = undefined
        let src          = rnd() % DICT
        var nw           = g_WordLen[src]
        for [i] in nw do
            tmp[i] = g_Bytes[g_WordOff[src] + i]

        for 2'u64
        {
            let p  = rnd() % nw
            let op = rnd() % 3
            let c  = cast(u8)(97 + (rnd() % 26))
            if op == 0
            {
                tmp[p] = c
            }
            elif op == 1
            {
                if nw > 2
                {
                    var i = p
                    while i + 1 < nw
                    {
                        tmp[i] = tmp[i + 1]
                        i += 1
                    }
                    nw -= 1
                }
            }
            else
            {
                var i = nw
                while i > p
                {
                    tmp[i] = tmp[i - 1]
                    i -= 1
                }
                tmp[p] = c
                nw += 1
            }
        }

        g_QOff[q] = qp
        g_QLen[q] = nw
        for [i] in nw
        {
            g_QBytes[qp] = tmp[i]
            qp += 1
        }
    }

    // ---- timed work ----
    let t0 = now()

    var row0: [64] u64 = undefined
    var row1: [64] u64 = undefined

    var check = 0's64
    for [q] in QUERIES
    {
        let ao      = g_QOff[q]
        let la      = g_QLen[q]
        var best    = 1073741824'u64
        var bestIdx = -1's64

        for [i] in DICT
        {
            let bo = g_WordOff[i]
            let lb = g_WordLen[i]
            var d  = 0'u64
            if la > lb do
                d = la - lb
            else do
                d = lb - la
            if d > MAXLEN do
                continue

            for [j] in lb + 1 do
                row0[j] = j

            for [x] in la
            {
                row1[0] = x + 1
                let ca  = g_QBytes[ao + x]
                for [y] in lb
                {
                    var cost = 1'u64
                    if ca == g_Bytes[bo + y] do
                        cost = 0
                    var v   = row0[y] + cost
                    var v2  = row0[y + 1] + 1
                    if v2 < v do
                        v = v2
                    v2 = row1[y] + 1
                    if v2 < v do
                        v = v2
                    row1[y + 1] = v
                }
                for [j] in lb + 1 do
                    row0[j] = row1[j]
            }

            let dd = row0[lb]
            if dd < best
            {
                best    = dd
                bestIdx = cast(s64) i
            }
        }

        check += cast(s64) best * 31 + bestIdx
    }

    let t1 = now()
    report(cast(u64) check, t0, t1)
}
