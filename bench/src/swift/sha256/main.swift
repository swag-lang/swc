import WinSDK
import Foundation

let MSGSIZE = 8388608
let M32: UInt64 = 0xFFFFFFFF

var gSeed: UInt64 = 12345

func rnd() -> UInt64 {
    gSeed = (gSeed &* 16807) % 2147483647
    return gSeed
}

func now() -> Double {
    var c = LARGE_INTEGER()
    var f = LARGE_INTEGER()
    QueryPerformanceCounter(&c)
    QueryPerformanceFrequency(&f)
    return Double(c.QuadPart) / Double(f.QuadPart)
}

let KTAB: [UInt64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]

@inline(__always)
func rotr(_ x: UInt64, _ k: UInt64) -> UInt64 {
    return ((x >> k) | (x << (32 - k))) & M32
}

// The whole `#main` body lives in a function so that locals stay locals:
// top-level variables in main.swift are globals and defeat several optimisations.
func runMain() {
// ---- data generation (not timed) ----
var msg = [UInt8](repeating: 0, count: MSGSIZE)
for i in 0..<MSGSIZE {
    msg[i] = UInt8(rnd() % 256)
}

// ---- timed work ----
let t0 = now()

let totalBits = UInt64(MSGSIZE) &* 8
var nb = MSGSIZE
var buf = [UInt8](repeating: 0, count: MSGSIZE + 128)
for i in 0..<MSGSIZE {
    buf[i] = msg[i]
}
buf[nb] = 0x80
nb += 1
while (nb % 64) != 56 {
    buf[nb] = 0
    nb += 1
}
for s in 0..<8 {
    buf[nb] = UInt8((totalBits >> UInt64(56 - 8 * s)) & 0xFF)
    nb += 1
}

var h0: UInt64 = 0x6a09e667
var h1: UInt64 = 0xbb67ae85
var h2: UInt64 = 0x3c6ef372
var h3: UInt64 = 0xa54ff53a
var h4: UInt64 = 0x510e527f
var h5: UInt64 = 0x9b05688c
var h6: UInt64 = 0x1f83d9ab
var h7: UInt64 = 0x5be0cd19

var w = [UInt64](repeating: 0, count: 64)
let nblocks = nb / 64

for b in 0..<nblocks {
    let o = b * 64
    for t in 0..<16 {
        let p = o + t * 4
        w[t] = (UInt64(buf[p]) << 24) | (UInt64(buf[p + 1]) << 16) | (UInt64(buf[p + 2]) << 8) | UInt64(buf[p + 3])
    }

    for t in 16..<64 {
        let x = w[t - 15]
        let y = w[t - 2]
        let s0 = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3)
        let s1 = rotr(y, 17) ^ rotr(y, 19) ^ (y >> 10)
        w[t] = (w[t - 16] &+ s0 &+ w[t - 7] &+ s1) & M32
    }

    var a = h0
    var bb = h1
    var c = h2
    var d = h3
    var e = h4
    var f = h5
    var g = h6
    var h = h7

    for i in 0..<64 {
        let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
        let ch = (e & f) ^ ((~e & M32) & g)
        let t1 = (h &+ s1 &+ ch &+ KTAB[i] &+ w[i]) & M32
        let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
        let maj = (a & bb) ^ (a & c) ^ (bb & c)
        let t2 = (s0 &+ maj) & M32
        h = g
        g = f
        f = e
        e = (d &+ t1) & M32
        d = c
        c = bb
        bb = a
        a = (t1 &+ t2) & M32
    }

    h0 = (h0 &+ a) & M32
    h1 = (h1 &+ bb) & M32
    h2 = (h2 &+ c) & M32
    h3 = (h3 &+ d) & M32
    h4 = (h4 &+ e) & M32
    h5 = (h5 &+ f) & M32
    h6 = (h6 &+ g) & M32
    h7 = (h7 &+ h) & M32
}

let check = h0 ^ h1 ^ h2 ^ h3 ^ h4 ^ h5 ^ h6 ^ h7

let t1 = now()
print(String(format: "CHECK=%llu MS=%.6f", check, (t1 - t0) * 1000.0))
}

runMain()
