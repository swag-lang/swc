const ROWS = 400000'u64

const REGIONS: [8] string = ["EMEA", "APAC", "AMER", "LATAM", "NORDIC", "IBERIA", "BENELUX", "DACH"]

func writeUInt(buf: [*] u8, pos, v: u64)->u64
{
    var tmp: [24] u8
    var n                = 0'u64
    var x                = v
    if x == 0
    {
        tmp[0] = '0'
        n      = 1
    }
    while x > 0
    {
        tmp[n] = cast(u8)(48 + (x % 10))
        n += 1
        x /= 10
    }

    var p = pos
    var i = n
    while i > 0
    {
        i -= 1
        buf[p] = tmp[i]
        p += 1
    }
    return p
}

func writeUInt2(buf: [*] u8, pos, v: u64)->u64
{
    buf[pos]     = cast(u8)(48 + (v / 10))
    buf[pos + 1] = cast(u8)(48 + (v % 10))
    return pos + 2
}

#main
{
    // ---- data generation (not timed) ----
    let text = cast([*] u8) (benchAlloc(ROWS * 48))!
    var n    = 0'u64

    for j in ROWS
    {
        if j > 0
        {
            text[n] = '\n'
            n += 1
        }

        let region = REGIONS[rnd() % 8]
        let y      = 2024 + (rnd() % 3)
        let m      = 1 + (rnd() % 12)
        let d      = 1 + (rnd() % 28)
        let qty    = 1 + (rnd() % 50)
        let cents  = 100 + (rnd() % 99900)

        n       = writeUInt(text, n, j)
        text[n] = ','
        n += 1
        for i in region.count
        {
            text[n] = region[i]
            n += 1
        }
        text[n] = ','
        n += 1
        n       = writeUInt(text, n, y)
        text[n] = '-'
        n += 1
        n       = writeUInt2(text, n, m)
        text[n] = '-'
        n += 1
        n       = writeUInt2(text, n, d)
        text[n] = ','
        n += 1
        n       = writeUInt(text, n, qty)
        text[n] = ','
        n += 1
        n       = writeUInt(text, n, cents / 100)
        text[n] = '.'
        n += 1
        n = writeUInt2(text, n, cents % 100)
    }

    // ---- timed work ----
    let t0 = now()

    var agg: ByteMap
    mapInit(&agg, 64, text)

    var slotCount = cast([*] u64) (benchAlloc(64 * #sizeof(u64)))!
    var slotQty   = cast([*] u64) (benchAlloc(64 * #sizeof(u64)))!
    var slotRev   = cast([*] f64) (benchAlloc(64 * #sizeof(f64)))!
    var slotMax   = cast([*] f64) (benchAlloc(64 * #sizeof(f64)))!

    var pos  = 0'u64
    var rows = 0'u64

    while pos < n
    {
        var eol = pos
        while eol < n and text[eol] != '\n' do
            eol += 1

        // field 0: id
        var p = pos
        while p < eol and text[p] != ',' do
            p += 1
        p += 1

        // field 1: region
        let rs = p
        while p < eol and text[p] != ',' do
            p += 1
        let rlen = p - rs
        p += 1

        // field 2: date (skipped)
        while p < eol and text[p] != ',' do
            p += 1
        p += 1

        // field 3: qty
        var qty = 0'u64
        while p < eol and text[p] != ','
        {
            qty = qty * 10 + cast(u64)(text[p] - 48)
            p += 1
        }
        p += 1

        // field 4: price
        var ip = 0'u64
        while p < eol and text[p] != '.'
        {
            ip = ip * 10 + cast(u64)(text[p] - 48)
            p += 1
        }
        p += 1
        var fr = 0'u64
        while p < eol
        {
            fr = fr * 10 + cast(u64)(text[p] - 48)
            p += 1
        }
        let price = cast(f64) ip + cast(f64) fr / 100.0'f64

        let idx = mapProbe(&agg, rs, rlen)
        if agg.used[idx] == 0
        {
            let slot = agg.count
            mapClaim(&agg, idx, rs, rlen, slot)
            slotCount[slot] = 1
            slotQty[slot]   = qty
            slotRev[slot]   = cast(f64) qty * price
            slotMax[slot]   = price
        }
        else
        {
            let slot = agg.val[idx]
            slotCount[slot] += 1
            slotQty[slot] += qty
            slotRev[slot] += cast(f64) qty * price
            if price > slotMax[slot] do
                slotMax[slot] = price
        }

        rows += 1
        pos = eol + 1
    }

    // sort the region keys, then fold them in order
    var order: [64] u64
    var keyIdx: [64] u64
    var nk               = 0'u64
    for i in 64'u64
    {
        if agg.used[i] != 0
        {
            keyIdx[nk] = i
            nk += 1
        }
    }

    for i in nk do
        order[i] = i
    for i in nk
    {
        var best = i
        for j in nk
        {
            if j <= i do
                continue
            let a  = keyIdx[order[best]]
            let b  = keyIdx[order[j]]
            var la = agg.keyLen[a]
            if agg.keyLen[b] < la do
                la = agg.keyLen[b]
            let c = Swag.memcmp(&text[agg.keyOff[b]], &text[agg.keyOff[a]], la)
            if c < 0 or (c == 0 and agg.keyLen[b] < agg.keyLen[a]) do
                best = j
        }
        let t      = order[i]
        order[i]   = order[best]
        order[best] = t
    }

    var check = rows
    for k in nk
    {
        let slot = agg.val[keyIdx[order[k]]]
        check += (k + 1) * (cast(u64)(slotRev[slot] * 100.0'f64 + 0.5'f64) % 1000003)
        check += slotCount[slot] + slotQty[slot] + cast(u64)(slotMax[slot] * 100.0'f64 + 0.5'f64)
    }

    let t1 = now()
    report(check, t0, t1)
}
