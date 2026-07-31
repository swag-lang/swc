import WinSDK
import Foundation

let ROWS = 400000

let REGIONS: [[UInt8]] = [
    Array("EMEA".utf8), Array("APAC".utf8), Array("AMER".utf8), Array("LATAM".utf8),
    Array("NORDIC".utf8), Array("IBERIA".utf8), Array("BENELUX".utf8), Array("DACH".utf8),
]

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

func memCmp(_ b: [UInt8], _ a: Int, _ c: Int, _ n: Int) -> Int {
    for i in 0..<n where b[a + i] != b[c + i] {
        return b[a + i] < b[c + i] ? -1 : 1
    }
    return 0
}

struct ByteMap {
    var keyOff: [Int]
    var keyLen: [Int]
    var val: [Int]
    var used: [UInt8]
    var mask: Int
    var count: Int

    init(_ capacity: Int) {
        keyOff = [Int](repeating: 0, count: capacity)
        keyLen = [Int](repeating: 0, count: capacity)
        val = [Int](repeating: 0, count: capacity)
        used = [UInt8](repeating: 0, count: capacity)
        mask = capacity - 1
        count = 0
    }

    func probe(_ base: [UInt8], _ off: Int, _ len: Int) -> Int {
        var h: UInt64 = 2166136261
        for i in 0..<len {
            h ^= UInt64(base[off + i])
            h = (h &* 16777619) & 0xFFFFFFFF
        }

        var idx = Int(h) & mask
        while used[idx] != 0 {
            if keyLen[idx] == len && memCmp(base, keyOff[idx], off, len) == 0 {
                return idx
            }
            idx = (idx + 1) & mask
        }

        return idx
    }

    mutating func claim(_ idx: Int, _ off: Int, _ len: Int, _ value: Int) {
        used[idx] = 1
        keyOff[idx] = off
        keyLen[idx] = len
        val[idx] = value
        count += 1
    }
}

func writeUInt(_ buf: inout [UInt8], _ pos: Int, _ v: UInt64) -> Int {
    var tmp = [UInt8](repeating: 0, count: 24)
    var n = 0
    var x = v
    if x == 0 {
        tmp[0] = 48
        n = 1
    }
    while x > 0 {
        tmp[n] = UInt8(48 &+ (x % 10))
        n += 1
        x /= 10
    }

    var p = pos
    var i = n
    while i > 0 {
        i -= 1
        buf[p] = tmp[i]
        p += 1
    }
    return p
}

func writeUInt2(_ buf: inout [UInt8], _ pos: Int, _ v: UInt64) -> Int {
    buf[pos] = UInt8(48 &+ (v / 10))
    buf[pos + 1] = UInt8(48 &+ (v % 10))
    return pos + 2
}

// The whole `#main` body lives in a function so that locals stay locals:
// top-level variables in main.swift are globals and defeat several optimisations.
func runMain() {
// ---- data generation (not timed) ----
var text = [UInt8](repeating: 0, count: ROWS * 48)
var n = 0

for j in 0..<ROWS {
    if j > 0 {
        text[n] = 10
        n += 1
    }

    let region = REGIONS[Int(rnd() % 8)]
    let y = 2024 &+ (rnd() % 3)
    let m = 1 &+ (rnd() % 12)
    let d = 1 &+ (rnd() % 28)
    let qty = 1 &+ (rnd() % 50)
    let cents = 100 &+ (rnd() % 99900)

    n = writeUInt(&text, n, UInt64(j))
    text[n] = 44
    n += 1
    for i in 0..<region.count {
        text[n] = region[i]
        n += 1
    }
    text[n] = 44
    n += 1
    n = writeUInt(&text, n, y)
    text[n] = 45
    n += 1
    n = writeUInt2(&text, n, m)
    text[n] = 45
    n += 1
    n = writeUInt2(&text, n, d)
    text[n] = 44
    n += 1
    n = writeUInt(&text, n, qty)
    text[n] = 44
    n += 1
    n = writeUInt(&text, n, cents / 100)
    text[n] = 46
    n += 1
    n = writeUInt2(&text, n, cents % 100)
}

// ---- timed work ----
let t0 = now()

var agg = ByteMap(64)

var slotCount = [UInt64](repeating: 0, count: 64)
var slotQty = [UInt64](repeating: 0, count: 64)
var slotRev = [Double](repeating: 0, count: 64)
var slotMax = [Double](repeating: 0, count: 64)

var pos = 0
var rows: UInt64 = 0

while pos < n {
    var eol = pos
    while eol < n && text[eol] != 10 {
        eol += 1
    }

    // field 0: id
    var p = pos
    while p < eol && text[p] != 44 {
        p += 1
    }
    p += 1

    // field 1: region
    let rs = p
    while p < eol && text[p] != 44 {
        p += 1
    }
    let rlen = p - rs
    p += 1

    // field 2: date (skipped)
    while p < eol && text[p] != 44 {
        p += 1
    }
    p += 1

    // field 3: qty
    var qty: UInt64 = 0
    while p < eol && text[p] != 44 {
        qty = qty &* 10 &+ UInt64(text[p] - 48)
        p += 1
    }
    p += 1

    // field 4: price
    var ip: UInt64 = 0
    while p < eol && text[p] != 46 {
        ip = ip &* 10 &+ UInt64(text[p] - 48)
        p += 1
    }
    p += 1
    var fr: UInt64 = 0
    while p < eol {
        fr = fr &* 10 &+ UInt64(text[p] - 48)
        p += 1
    }
    let price = Double(ip) + Double(fr) / 100.0

    let idx = agg.probe(text, rs, rlen)
    if agg.used[idx] == 0 {
        let slot = agg.count
        agg.claim(idx, rs, rlen, slot)
        slotCount[slot] = 1
        slotQty[slot] = qty
        slotRev[slot] = Double(qty) * price
        slotMax[slot] = price
    } else {
        let slot = agg.val[idx]
        slotCount[slot] += 1
        slotQty[slot] &+= qty
        slotRev[slot] += Double(qty) * price
        if price > slotMax[slot] {
            slotMax[slot] = price
        }
    }

    rows += 1
    pos = eol + 1
}

// sort the region keys, then fold them in order
var order = [Int](repeating: 0, count: 64)
var keyIdx = [Int](repeating: 0, count: 64)
var nk = 0
for i in 0..<64 where agg.used[i] != 0 {
    keyIdx[nk] = i
    nk += 1
}

for i in 0..<nk {
    order[i] = i
}
for i in 0..<nk {
    var best = i
    for j in 0..<nk {
        if j <= i {
            continue
        }
        let a = keyIdx[order[best]]
        let b = keyIdx[order[j]]
        var la = agg.keyLen[a]
        if agg.keyLen[b] < la {
            la = agg.keyLen[b]
        }
        let c = memCmp(text, agg.keyOff[b], agg.keyOff[a], la)
        if c < 0 || (c == 0 && agg.keyLen[b] < agg.keyLen[a]) {
            best = j
        }
    }
    order.swapAt(i, best)
}

var check = rows
for k in 0..<nk {
    let slot = agg.val[keyIdx[order[k]]]
    check &+= UInt64(k + 1) &* (UInt64(slotRev[slot] * 100.0 + 0.5) % 1000003)
    check &+= slotCount[slot] &+ slotQty[slot] &+ UInt64(slotMax[slot] * 100.0 + 0.5)
}

let t1 = now()
print(String(format: "CHECK=%llu MS=%.6f", check, (t1 - t0) * 1000.0))
}

runMain()
