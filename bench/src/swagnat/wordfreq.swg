const VOCAB = 5000'u64
const WORDS = 2000000'u64
const CAP   = 16384'u64

var g_Text: [*] u8  = undefined
var g_Cnt:  [*] u64 = undefined
var g_Off:  [*] u64 = undefined
var g_Len:  [*] u64 = undefined
var g_Idx:  [*] u64 = undefined

// count descending, then key bytes ascending
func less(a, b: u64)->bool
{
    if g_Cnt[a] != g_Cnt[b] do
        return g_Cnt[a] > g_Cnt[b]

    var n = g_Len[a]
    if g_Len[b] < n do
        n = g_Len[b]
    let c = Swag.memcmp(&g_Text[g_Off[a]], &g_Text[g_Off[b]], n)
    if c != 0 do
        return c < 0
    return g_Len[a] < g_Len[b]
}

func qsort(lowIn, highIn: s64)
{
    var low  = lowIn
    let high = highIn

    while low < high
    {
        let p = g_Idx[cast(u64)((low + high) / 2)]
        var i = low
        var j = high

        while i <= j
        {
            while less(g_Idx[cast(u64) i], p) do
                i += 1
            while less(p, g_Idx[cast(u64) j]) do
                j -= 1
            if i <= j
            {
                let t                = g_Idx[cast(u64) i]
                g_Idx[cast(u64) i]   = g_Idx[cast(u64) j]
                g_Idx[cast(u64) j]   = t
                i += 1
                j -= 1
            }
        }

        qsort(low, j)
        low = i
    }
}

#main
{
    // ---- data generation (not timed) ----
    let vocabBytes = cast([*] u8) (benchAlloc(VOCAB * 16))!
    let vocabOff   = cast([*] u64) (benchAlloc(VOCAB * #sizeof(u64)))!
    let vocabLen   = cast([*] u64) (benchAlloc(VOCAB * #sizeof(u64)))!

    var vp = 0'u64
    for i in VOCAB
    {
        var nn = i + 1
        let l  = 3 + (i % 6)
        vocabOff[i] = vp
        vocabLen[i] = l
        for k in l
        {
            vocabBytes[vp] = cast(u8)(97 + (nn % 26))
            vp += 1
            nn = nn / 26 + 7 * k
        }
    }

    g_Text = cast([*] u8) (benchAlloc(WORDS * 12))!
    var n  = 0'u64
    for j in WORDS
    {
        let idx = rnd() % VOCAB
        let o   = vocabOff[idx]
        let l   = vocabLen[idx]
        for k in l
        {
            g_Text[n] = vocabBytes[o + k]
            n += 1
        }
        if (j + 1) % 12 == 0 do
            g_Text[n] = '\n'
        else do
            g_Text[n] = ' '
        n += 1
    }

    // ---- timed work ----
    let t0 = now()

    var counts: ByteMap = undefined
    mapInit(&counts, CAP, g_Text)

    var start = 0'u64
    var open  = false
    var i     = 0'u64

    while i < n
    {
        let c = g_Text[i]
        if c >= 97 and c <= 122
        {
            if !open
            {
                start = i
                open  = true
            }
        }
        elif open
        {
            let idx = mapProbe(&counts, start, i - start)
            if counts.used[idx] == 0 do
                mapClaim(&counts, idx, start, i - start, 1)
            else do
                counts.val[idx] += 1
            open = false
        }
        i += 1
    }

    if open
    {
        let idx = mapProbe(&counts, start, n - start)
        if counts.used[idx] == 0 do
            mapClaim(&counts, idx, start, n - start, 1)
        else do
            counts.val[idx] += 1
    }

    let distinct = counts.count
    g_Cnt        = cast([*] u64) (benchAlloc(distinct * #sizeof(u64)))!
    g_Off        = cast([*] u64) (benchAlloc(distinct * #sizeof(u64)))!
    g_Len        = cast([*] u64) (benchAlloc(distinct * #sizeof(u64)))!
    g_Idx        = cast([*] u64) (benchAlloc(distinct * #sizeof(u64)))!

    var ni = 0'u64
    for s in CAP
    {
        if counts.used[s] == 0 do
            continue
        g_Cnt[ni] = counts.val[s]
        g_Off[ni] = counts.keyOff[s]
        g_Len[ni] = counts.keyLen[s]
        g_Idx[ni] = ni
        ni += 1
    }

    qsort(0, cast(s64) distinct - 1)

    var check = distinct * 7
    for k in 20'u64 do
        check += (k + 1) * g_Cnt[g_Idx[k]]

    let t1 = now()
    report(check, t0, t1)
}
