const DICT    = 6000_u64
const QUERIES = 40_u64
const MAXLEN  = 3_u64

late var g_Bytes:   [*] u8
late var g_WordOff: [*] u64
late var g_WordLen: [*] u64

late var g_QBytes: [*] u8
late var g_QOff:   [*] u64
late var g_QLen:   [*] u64

#run
{
    // ---- data generation (not timed) ----
    g_Bytes   = cast([*] u8, unwrap benchAlloc(DICT * 16))
    g_WordOff = cast([*] u64, unwrap benchAlloc(DICT * #sizeof(u64)))
    g_WordLen = cast([*] u64, unwrap benchAlloc(DICT * #sizeof(u64)))

    var wp = 0_u64
    for i in DICT
    {
        var n = i + 1
        let l = 4 + (i % 7)
        g_WordOff[i] = wp
        g_WordLen[i] = l
        for k in l
        {
            g_Bytes[wp] = cast(u8, (97 + (n % 26)))
            wp += 1
            n  = n / 26 + 7 * k
        }
    }

    g_QBytes = cast([*] u8, unwrap benchAlloc(QUERIES * 32))
    g_QOff   = cast([*] u64, unwrap benchAlloc(QUERIES * #sizeof(u64)))
    g_QLen   = cast([*] u64, unwrap benchAlloc(QUERIES * #sizeof(u64)))

    var qp = 0_u64
    for q in QUERIES
    {
        var tmp: [32] u8
        let src = rnd() % DICT
        var nw  = g_WordLen[src]
        for i in nw {
            tmp[i] = g_Bytes[g_WordOff[src] + i]

        }
        for 2_u64
        {
            let p  = rnd() % nw
            let op = rnd() % 3
            let c  = cast(u8, (97 + (rnd() % 26)))
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
                        i      += 1
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
                    i      -= 1
                }

                tmp[p] = c
                nw     += 1
            }
        }

        g_QOff[q] = qp
        g_QLen[q] = nw
        for i in nw
        {
            g_QBytes[qp] = tmp[i]
            qp += 1
        }
    }

    // ---- timed work ----
    let t0 = now()

    var row0: [64] u64
    var row1: [64] u64

    var check = 0_s64
    for q in QUERIES
    {
        let ao      = g_QOff[q]
        let la      = g_QLen[q]
        var best    = 1073741824_u64
        var bestIdx = -1_s64

        for i in DICT
        {
            let bo = g_WordOff[i]
            let lb = g_WordLen[i]
            var d  = 0_u64
            if la > lb {
                d = la - lb
            }
            else {
                d = lb - la
            }
            if d > MAXLEN {
                continue

            }
            for j in lb + 1 {
                row0[j] = j

            }
            for x in la
            {
                row1[0] = x + 1
                let ca = g_QBytes[ao + x]
                for y in lb
                {
                    var cost = 1_u64
                    if ca == g_Bytes[bo + y] {
                        cost = 0
                    }
                    var v  = row0[y] + cost
                    var v2 = row0[y + 1] + 1
                    if v2 < v {
                        v = v2
                    }
                    v2 = row1[y] + 1
                    if v2 < v {
                        v = v2
                    }
                    row1[y + 1] = v
                }

                for j in lb + 1 {
                    row0[j] = row1[j]
                }
            }

            let dd = row0[lb]
            if dd < best
            {
                best    = dd
                bestIdx = cast(s64, i)
            }
        }

        check += cast(s64, best) * 31 + bestIdx
    }

    let t1 = now()
    report(cast(u64, check), t0, t1)
}
