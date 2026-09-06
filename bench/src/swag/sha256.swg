const SIZE = 8388608'u64
const M32  = 0xFFFFFFFF'u64

const KTAB: [64] u64 = [
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2]

func rotr(x, k: u64)->u64 => ((x >> k) | (x << (32 - k))) & M32

#run
{
    // ---- data generation (not timed) ----
    let msg = cast([*] u8) benchAlloc(SIZE)!
    for i in SIZE do
        msg[i] = cast(u8) (rnd() % 256)

    // ---- timed work ----
    let t0 = now()

    let totalBits = SIZE * 8
    var nb        = SIZE
    let buf       = cast([*] u8) (benchAlloc(SIZE + 128))!
    Swag.memcpy(buf, msg, SIZE)
    buf[nb] = 0x80
    nb      += 1
    while (nb % 64) != 56
    {
        buf[nb] = 0
        nb      += 1
    }

    for s in 8'u64
    {
        buf[nb] = cast(u8) ((totalBits >> (56 - 8 * s)) & 0xFF)
        nb      += 1
    }

    var h0 = 0x6A09E667'u64
    var h1 = 0xBB67AE85'u64
    var h2 = 0x3C6EF372'u64
    var h3 = 0xA54FF53A'u64
    var h4 = 0x510E527F'u64
    var h5 = 0x9B05688C'u64
    var h6 = 0x1F83D9AB'u64
    var h7 = 0x5BE0CD19'u64

    var w: [64] u64
    let nblocks = nb / 64

    for b in nblocks
    {
        let o = b * 64
        for t in 16'u64
        {
            let p = o + t * 4
            w[t] = (cast(u64) buf[p] << 24) | (cast(u64) buf[p + 1] << 16) | (cast(u64) buf[p + 2] << 8) | cast(u64) buf[p + 3]
        }

        var t = 16'u64
        while t < 64
        {
            let x  = w[t - 15]
            let y  = w[t - 2]
            let s0 = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3)
            let s1 = rotr(y, 17) ^ rotr(y, 19) ^ (y >> 10)
            w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & M32
            t    += 1
        }

        var a  = h0
        var bb = h1
        var c  = h2
        var d  = h3
        var e  = h4
        var f  = h5
        var g  = h6
        var h  = h7

        for i in 64'u64
        {
            let s1  = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
            let ch  = (e & f) ^ ((~e & M32) & g)
            let t1  = (h + s1 + ch + KTAB[i] + w[i]) & M32
            let s0  = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
            let maj = (a & bb) ^ (a & c) ^ (bb & c)
            let t2  = (s0 + maj) & M32
            h  = g
            g  = f
            f  = e
            e  = (d + t1) & M32
            d  = c
            c  = bb
            bb = a
            a  = (t1 + t2) & M32
        }

        h0 = (h0 + a) & M32
        h1 = (h1 + bb) & M32
        h2 = (h2 + c) & M32
        h3 = (h3 + d) & M32
        h4 = (h4 + e) & M32
        h5 = (h5 + f) & M32
        h6 = (h6 + g) & M32
        h7 = (h7 + h) & M32
    }

    let check = h0 ^ h1 ^ h2 ^ h3 ^ h4 ^ h5 ^ h6 ^ h7

    let t1 = now()
    report(check, t0, t1)

    benchFree(buf)
    benchFree(msg)
}
