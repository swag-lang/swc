import WinSDK
import Foundation

let VOCAB = 5000
let WORDS = 2000000
let CAP = 16384

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

struct ByteMap {
    var keyOff: [Int]
    var keyLen: [Int]
    var val: [UInt64]
    var used: [UInt8]
    var mask: Int
    var count: Int

    init(_ capacity: Int) {
        keyOff = [Int](repeating: 0, count: capacity)
        keyLen = [Int](repeating: 0, count: capacity)
        val = [UInt64](repeating: 0, count: capacity)
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
            if keyLen[idx] == len && memEq(base, keyOff[idx], off, len) {
                return idx
            }
            idx = (idx + 1) & mask
        }

        return idx
    }

    mutating func claim(_ idx: Int, _ off: Int, _ len: Int, _ value: UInt64) {
        used[idx] = 1
        keyOff[idx] = off
        keyLen[idx] = len
        val[idx] = value
        count += 1
    }
}

func memEq(_ b: [UInt8], _ a: Int, _ c: Int, _ n: Int) -> Bool {
    for i in 0..<n where b[a + i] != b[c + i] {
        return false
    }
    return true
}

func memCmp(_ b: [UInt8], _ a: Int, _ c: Int, _ n: Int) -> Int {
    for i in 0..<n where b[a + i] != b[c + i] {
        return b[a + i] < b[c + i] ? -1 : 1
    }
    return 0
}

var gText = [UInt8]()
var gCnt = [UInt64]()
var gOff = [Int]()
var gLen = [Int]()
var gIdx = [Int]()

// count descending, then key bytes ascending
func less(_ a: Int, _ b: Int) -> Bool {
    if gCnt[a] != gCnt[b] {
        return gCnt[a] > gCnt[b]
    }

    var n = gLen[a]
    if gLen[b] < n {
        n = gLen[b]
    }
    let c = memCmp(gText, gOff[a], gOff[b], n)
    if c != 0 {
        return c < 0
    }
    return gLen[a] < gLen[b]
}

func qsortIdx(_ lowIn: Int, _ highIn: Int) {
    var low = lowIn
    let high = highIn

    while low < high {
        let p = gIdx[(low + high) / 2]
        var i = low
        var j = high

        while i <= j {
            while less(gIdx[i], p) {
                i += 1
            }
            while less(p, gIdx[j]) {
                j -= 1
            }
            if i <= j {
                gIdx.swapAt(i, j)
                i += 1
                j -= 1
            }
        }

        qsortIdx(low, j)
        low = i
    }
}

// The whole `#main` body lives in a function so that locals stay locals:
// top-level variables in main.swift are globals and defeat several optimisations.
func runMain() {
// ---- data generation (not timed) ----
var vocabBytes = [UInt8](repeating: 0, count: VOCAB * 16)
var vocabOff = [Int](repeating: 0, count: VOCAB)
var vocabLen = [Int](repeating: 0, count: VOCAB)

var vp = 0
for i in 0..<VOCAB {
    var nn = UInt64(i + 1)
    let l = 3 + (i % 6)
    vocabOff[i] = vp
    vocabLen[i] = l
    for k in 0..<l {
        vocabBytes[vp] = UInt8(97 + (nn % 26))
        vp += 1
        nn = nn / 26 &+ 7 &* UInt64(k)
    }
}

gText = [UInt8](repeating: 0, count: WORDS * 12)
var n = 0
for j in 0..<WORDS {
    let idx = Int(rnd() % UInt64(VOCAB))
    let o = vocabOff[idx]
    let l = vocabLen[idx]
    for k in 0..<l {
        gText[n] = vocabBytes[o + k]
        n += 1
    }
    gText[n] = (j + 1) % 12 == 0 ? 10 : 32
    n += 1
}

// ---- timed work ----
let t0 = now()

var counts = ByteMap(CAP)

var start = 0
var open = false
var i = 0

while i < n {
    let c = gText[i]
    if c >= 97 && c <= 122 {
        if !open {
            start = i
            open = true
        }
    } else if open {
        let idx = counts.probe(gText, start, i - start)
        if counts.used[idx] == 0 {
            counts.claim(idx, start, i - start, 1)
        } else {
            counts.val[idx] += 1
        }
        open = false
    }
    i += 1
}

if open {
    let idx = counts.probe(gText, start, n - start)
    if counts.used[idx] == 0 {
        counts.claim(idx, start, n - start, 1)
    } else {
        counts.val[idx] += 1
    }
}

let distinct = counts.count
gCnt = [UInt64](repeating: 0, count: distinct)
gOff = [Int](repeating: 0, count: distinct)
gLen = [Int](repeating: 0, count: distinct)
gIdx = [Int](repeating: 0, count: distinct)

var ni = 0
for s in 0..<CAP {
    if counts.used[s] == 0 {
        continue
    }
    gCnt[ni] = counts.val[s]
    gOff[ni] = counts.keyOff[s]
    gLen[ni] = counts.keyLen[s]
    gIdx[ni] = ni
    ni += 1
}

qsortIdx(0, distinct - 1)

var check = UInt64(distinct) &* 7
for k in 0..<20 {
    check &+= UInt64(k + 1) &* gCnt[gIdx[k]]
}

let t1 = now()
print(String(format: "CHECK=%llu MS=%.6f", check, (t1 - t0) * 1000.0))
}

runMain()
