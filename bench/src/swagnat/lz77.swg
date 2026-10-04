const DATA_SIZE = 1'u64 << 20
const WORDS     = 512'u64
const HASH_SIZE = 65536'u64
const WINDOW    = 32768's64
const MIN_MATCH = 4's64
const MAX_MATCH = 258's64
const MAX_CHAIN = 32's64

func hashAt(d: [*] u8, p: s64)->u64
{
    return (((cast(u64) d[p] * 33 + d[p + 1]) * 33 + d[p + 2]) * 33 + d[p + 3]) % HASH_SIZE
}

#main
{
    // ---- data generation (not timed) ----
    let letters   = cast([*] u8) (benchAlloc(WORDS * 10))!
    let wordStart = cast([*] u64) (benchAlloc(WORDS * #sizeof(u64)))!
    let wordLen   = cast([*] u64) (benchAlloc(WORDS * #sizeof(u64)))!
    var used      = 0'u64
    for k in WORDS
    {
        let len = 2 + rnd() % 8
        wordStart[k] = used
        wordLen[k]   = len
        for j in len do
            letters[used + j] = cast(u8) (97 + rnd() % 26)
        used += len
    }

    let n    = cast(s64) DATA_SIZE
    let data = cast([*] u8) (benchAlloc(DATA_SIZE))!
    var pos  = 0's64
    while pos < n
    {
        let w = rnd() % WORDS
        var j = 0'u64
        while j < wordLen[w] and pos < n
        {
            data[pos] = letters[wordStart[w] + j]
            pos       += 1
            j         += 1
        }

        if pos < n
        {
            data[pos] = ' '
            pos       += 1
        }
    }

    // ---- timed work ----
    let t0 = now()

    let head = cast([*] s64) (benchAlloc(HASH_SIZE * #sizeof(s64)))!
    let prev = cast([*] s64) (benchAlloc(cast(u64) WINDOW * #sizeof(s64)))!
    for i in HASH_SIZE do
        head[i] = -1
    for i in WINDOW do
        prev[i] = -1

    let comp  = cast([*] u8) (benchAlloc(DATA_SIZE * 2 + 16))!
    var csize = 0's64

    var i = 0's64
    while i + MIN_MATCH <= n
    {
        var best  = 0's64
        var dist  = 0's64
        let limit = n - i < MAX_MATCH ? n - i : MAX_MATCH
        let h     = hashAt(data, i)
        var cand  = head[h]
        var chain = 0's64
        while cand >= 0 and i - cand < WINDOW and chain < MAX_CHAIN
        {
            var l = 0's64
            while l < limit and data[cand + l] == data[i + l] do
                l += 1
            if l > best
            {
                best = l
                dist = i - cand
                if l == limit do
                    break
            }

            cand  = prev[cand % WINDOW]
            chain += 1
        }

        prev[i % WINDOW] = head[h]
        head[h] = i

        if best >= MIN_MATCH
        {
            comp[csize]     = 1
            comp[csize + 1] = cast(u8) (best - MIN_MATCH)
            comp[csize + 2] = cast(u8) ((dist - 1) % 256)
            comp[csize + 3] = cast(u8) ((dist - 1) / 256)
            csize           += 4
            for p in i + 1 until i + best
            {
                if p + MIN_MATCH <= n
                {
                    let hp = hashAt(data, p)
                    prev[p % WINDOW] = head[hp]
                    head[hp]         = p
                }
            }

            i += best
        }
        else
        {
            comp[csize]     = 0
            comp[csize + 1] = data[i]
            csize           += 2
            i               += 1
        }
    }

    while i < n
    {
        comp[csize]     = 0
        comp[csize + 1] = data[i]
        csize           += 2
        i               += 1
    }

    // ---- decompress and verify ----
    let out = cast([*] u8) (benchAlloc(DATA_SIZE))!
    var o   = 0's64
    var c   = 0's64
    while c < csize
    {
        if comp[c] == 0
        {
            out[o] = comp[c + 1]
            o      += 1
            c      += 2
        }
        else
        {
            let len  = cast(s64) comp[c + 1] + MIN_MATCH
            let back = cast(s64) comp[c + 2] + cast(s64) comp[c + 3] * 256 + 1
            for len
            {
                out[o] = out[o - back]
                o      += 1
            }

            c += 4
        }
    }

    var same = o == n
    var k    = 0's64
    while same and k < n
    {
        if out[k] != data[k] do
            same = false
        k += 1
    }

    var hc = 0'u64
    for k in csize do
        hc = (hc * 31 + comp[k]) % 1000003

    let check = same ? cast(u64) csize * 1000003 + hc : 0

    let t1 = now()
    report(check, t0, t1)

    benchFree(out)
    benchFree(comp)
    benchFree(prev)
    benchFree(head)
    benchFree(data)
    benchFree(wordLen)
    benchFree(wordStart)
    benchFree(letters)
}
