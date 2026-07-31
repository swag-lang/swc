import WinSDK
import Foundation

let DICT = 6000
let QUERIES = 40
let MAXLEN = 3

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

// The whole `#main` body lives in a function so that locals stay locals:
// top-level variables in main.swift are globals and defeat several optimisations.
func runMain() {
// ---- data generation (not timed) ----
var bytes = [UInt8](repeating: 0, count: DICT * 16)
var wordOff = [Int](repeating: 0, count: DICT)
var wordLen = [Int](repeating: 0, count: DICT)

var wp = 0
for i in 0..<DICT {
    var n = UInt64(i + 1)
    let l = 4 + (i % 7)
    wordOff[i] = wp
    wordLen[i] = l
    for k in 0..<l {
        bytes[wp] = UInt8(97 + (n % 26))
        wp += 1
        n = n / 26 &+ 7 &* UInt64(k)
    }
}

var qBytes = [UInt8](repeating: 0, count: QUERIES * 32)
var qOff = [Int](repeating: 0, count: QUERIES)
var qLen = [Int](repeating: 0, count: QUERIES)

var qp = 0
for q in 0..<QUERIES {
    var tmp = [UInt8](repeating: 0, count: 32)
    let src = Int(rnd() % UInt64(DICT))
    var nw = wordLen[src]
    for i in 0..<nw {
        tmp[i] = bytes[wordOff[src] + i]
    }

    for _ in 0..<2 {
        let p = Int(rnd() % UInt64(nw))
        let op = rnd() % 3
        let c = UInt8(97 + (rnd() % 26))
        if op == 0 {
            tmp[p] = c
        } else if op == 1 {
            if nw > 2 {
                var i = p
                while i + 1 < nw {
                    tmp[i] = tmp[i + 1]
                    i += 1
                }
                nw -= 1
            }
        } else {
            var i = nw
            while i > p {
                tmp[i] = tmp[i - 1]
                i -= 1
            }
            tmp[p] = c
            nw += 1
        }
    }

    qOff[q] = qp
    qLen[q] = nw
    for i in 0..<nw {
        qBytes[qp] = tmp[i]
        qp += 1
    }
}

// ---- timed work ----
let t0 = now()

var row0 = [UInt64](repeating: 0, count: 64)
var row1 = [UInt64](repeating: 0, count: 64)

var check: Int64 = 0
for q in 0..<QUERIES {
    let ao = qOff[q]
    let la = qLen[q]
    var best: UInt64 = 1073741824
    var bestIdx: Int64 = -1

    for i in 0..<DICT {
        let bo = wordOff[i]
        let lb = wordLen[i]
        let d = la > lb ? la - lb : lb - la
        if d > MAXLEN {
            continue
        }

        for j in 0...lb {
            row0[j] = UInt64(j)
        }

        for x in 0..<la {
            row1[0] = UInt64(x + 1)
            let ca = qBytes[ao + x]
            for y in 0..<lb {
                let cost: UInt64 = ca == bytes[bo + y] ? 0 : 1
                var v = row0[y] &+ cost
                var v2 = row0[y + 1] &+ 1
                if v2 < v {
                    v = v2
                }
                v2 = row1[y] &+ 1
                if v2 < v {
                    v = v2
                }
                row1[y + 1] = v
            }
            for j in 0...lb {
                row0[j] = row1[j]
            }
        }

        let dd = row0[lb]
        if dd < best {
            best = dd
            bestIdx = Int64(i)
        }
    }

    check &+= Int64(best) &* 31 &+ bestIdx
}

let t1 = now()
print(String(format: "CHECK=%llu MS=%.6f", UInt64(bitPattern: check), (t1 - t0) * 1000.0))
}

runMain()
