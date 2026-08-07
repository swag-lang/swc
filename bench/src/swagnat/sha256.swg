const SIZE = 8388608'u64
const M32  = 0xFFFFFFFF'u64

const KTAB: [64] u64 = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]

func rotr(x, k: u64)->u64 => ((x >> k) | (x << (32 - k))) & M32

#main
{
    // ---- data generation (not timed) ----
    let msg = cast([*] u8) @alloc(SIZE)!
    for [i] in SIZE do
        msg[i] = cast(u8)(rnd() % 256)

    // ---- timed work ----
    let t0 = now()

    let totalBits = SIZE * 8
    var nb        = SIZE
    let buf       = cast([*] u8) (@alloc(SIZE + 128))!
    @memcpy(buf, msg, SIZE)
    buf[nb] = 0x80
    nb += 1
    while (nb % 64) != 56
    {
        buf[nb] = 0
        nb += 1
    }
    for [s] in 8'u64
    {
        buf[nb] = cast(u8)((totalBits >> (56 - 8 * s)) & 0xFF)
        nb += 1
    }

    var h0 = 0x6a09e667'u64
    var h1 = 0xbb67ae85'u64
    var h2 = 0x3c6ef372'u64
    var h3 = 0xa54ff53a'u64
    var h4 = 0x510e527f'u64
    var h5 = 0x9b05688c'u64
    var h6 = 0x1f83d9ab'u64
    var h7 = 0x5be0cd19'u64

    var w: [64] u64 = undefined
    let nblocks     = nb / 64

    for [b] in nblocks
    {
        let o = b * 64
        for [t] in 16'u64
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
            w[t]   = (w[t - 16] + s0 + w[t - 7] + s1) & M32
            t += 1
        }

        var a  = h0
        var bb = h1
        var c  = h2
        var d  = h3
        var e  = h4
        var f  = h5
        var g  = h6
        var h  = h7

        for [i] in 64'u64
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

    @free(buf)
    @free(msg)
}
