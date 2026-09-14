package main

import common "common"

MSGSIZE :: u64(8388608)
M32 :: 0xFFFFFFFF
KTAB: [64]u64 = [64]u64{
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
rotr :: proc(x: u64, k: u64) -> u64 {
    return (((x >> k) | (x << (32 - k))) & M32)
}

main :: proc() {
    msg: [^]u8 = ([^]u8)(common.xalloc(MSGSIZE))
    for i: u64 = 0; (i < MSGSIZE); i += 1 {
        msg[i] = u8((common.rnd() % 256))
    }
    // Timed work starts after data generation.
    t0: f64 = common.now()
    totalBits: u64 = (MSGSIZE * 8)
    nb: u64 = MSGSIZE
    buf: [^]u8 = ([^]u8)(common.xalloc((MSGSIZE + 128)))
    common.memcpy(buf, msg, MSGSIZE)
    buf[nb] = 0x80
    nb += 1
    for ((nb % 64) != 56) {
        buf[nb] = 0
        nb += 1
    }
    for s: u64 = 0; (s < 8); s += 1 {
        buf[nb] = u8(((totalBits >> (56 - (8 * s))) & 0xFF))
        nb += 1
    }
    h0: u64 = 0x6a09e667
    h1: u64 = 0xbb67ae85
    h2: u64 = 0x3c6ef372
    h3: u64 = 0xa54ff53a
    h4: u64 = 0x510e527f
    h5: u64 = 0x9b05688c
    h6: u64 = 0x1f83d9ab
    h7: u64 = 0x5be0cd19
    w: [64]u64
    nblocks: u64 = (nb / 64)
    for b: u64 = 0; (b < nblocks); b += 1 {
        o: u64 = (b * 64)
        for t: u64 = 0; (t < 16); t += 1 {
            p: u64 = (o + (t * 4))
            w[t] = ((((u64(buf[p]) << 24) | (u64(buf[(p + 1)]) << 16)) | (u64(buf[(p + 2)]) << 8)) | u64(buf[(p + 3)]))
        }
        t: u64 = 16
        for (t < 64) {
            x: u64 = w[(t - 15)]
            y: u64 = w[(t - 2)]
            s0: u64 = ((rotr(x, 7) ~ rotr(x, 18)) ~ (x >> 3))
            s1: u64 = ((rotr(y, 17) ~ rotr(y, 19)) ~ (y >> 10))
            w[t] = ((((w[(t - 16)] + s0) + w[(t - 7)]) + s1) & M32)
            t += 1
        }
        a: u64 = h0
        bb: u64 = h1
        c: u64 = h2
        d: u64 = h3
        e: u64 = h4
        f: u64 = h5
        g: u64 = h6
        h: u64 = h7
        for i: u64 = 0; (i < 64); i += 1 {
            s1: u64 = ((rotr(e, 6) ~ rotr(e, 11)) ~ rotr(e, 25))
            ch: u64 = ((e & f) ~ ((~e & M32) & g))
            t1: u64 = (((((h + s1) + ch) + KTAB[i]) + w[i]) & M32)
            s0: u64 = ((rotr(a, 2) ~ rotr(a, 13)) ~ rotr(a, 22))
            maj: u64 = (((a & bb) ~ (a & c)) ~ (bb & c))
            t2: u64 = ((s0 + maj) & M32)
            h = g
            g = f
            f = e
            e = ((d + t1) & M32)
            d = c
            c = bb
            bb = a
            a = ((t1 + t2) & M32)
        }
        h0 = ((h0 + a) & M32)
        h1 = ((h1 + bb) & M32)
        h2 = ((h2 + c) & M32)
        h3 = ((h3 + d) & M32)
        h4 = ((h4 + e) & M32)
        h5 = ((h5 + f) & M32)
        h6 = ((h6 + g) & M32)
        h7 = ((h7 + h) & M32)
    }
    check: u64 = (((((((h0 ~ h1) ~ h2) ~ h3) ~ h4) ~ h5) ~ h6) ~ h7)
    t1: f64 = common.now()
    common.report(check, t0, t1)
    common.free(buf)
    common.free(msg)
    return
}

