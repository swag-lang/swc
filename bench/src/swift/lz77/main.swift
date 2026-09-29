import WinSDK
import Foundation

let DATA_SIZE = 1 << 20
let WORDS = 512
let HASH_SIZE = 65536
let WINDOW = 32768
let MIN_MATCH = 4
let MAX_MATCH = 258
let MAX_CHAIN = 32

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

@inline(__always)
func hashAt(_ d: [UInt8], _ p: Int) -> Int {
    return (((Int(d[p]) * 33 + Int(d[p + 1])) * 33 + Int(d[p + 2])) * 33 + Int(d[p + 3])) % HASH_SIZE
}

func runMain() {
    // ---- data generation (not timed) ----
    var letters = [UInt8](repeating: 0, count: WORDS * 10)
    var wordStart = [Int](repeating: 0, count: WORDS)
    var wordLen = [Int](repeating: 0, count: WORDS)
    var used = 0
    for k in 0..<WORDS {
        let len = 2 + Int(rnd() % 8)
        wordStart[k] = used
        wordLen[k] = len
        for j in 0..<len {
            letters[used + j] = UInt8(97 + rnd() % 26)
        }
        used += len
    }

    let n = DATA_SIZE
    var data = [UInt8](repeating: 0, count: n)
    var pos = 0
    while pos < n {
        let w = Int(rnd() % UInt64(WORDS))
        var j = 0
        while j < wordLen[w] && pos < n {
            data[pos] = letters[wordStart[w] + j]
            pos += 1
            j += 1
        }
        if pos < n {
            data[pos] = 32
            pos += 1
        }
    }

    // ---- timed work ----
    let t0 = now()

    var head = [Int](repeating: -1, count: HASH_SIZE)
    var prev = [Int](repeating: -1, count: WINDOW)

    var comp = [UInt8](repeating: 0, count: n * 2 + 16)
    var csize = 0

    var i = 0
    while i + MIN_MATCH <= n {
        var best = 0
        var dist = 0
        let limit = n - i < MAX_MATCH ? n - i : MAX_MATCH
        let h = hashAt(data, i)
        var cand = head[h]
        var chain = 0
        while cand >= 0 && i - cand < WINDOW && chain < MAX_CHAIN {
            var l = 0
            while l < limit && data[cand + l] == data[i + l] {
                l += 1
            }
            if l > best {
                best = l
                dist = i - cand
                if l == limit {
                    break
                }
            }
            cand = prev[cand % WINDOW]
            chain += 1
        }

        prev[i % WINDOW] = head[h]
        head[h] = i

        if best >= MIN_MATCH {
            comp[csize] = 1
            comp[csize + 1] = UInt8(best - MIN_MATCH)
            comp[csize + 2] = UInt8((dist - 1) % 256)
            comp[csize + 3] = UInt8((dist - 1) / 256)
            csize += 4
            var p = i + 1
            while p < i + best {
                if p + MIN_MATCH <= n {
                    let hp = hashAt(data, p)
                    prev[p % WINDOW] = head[hp]
                    head[hp] = p
                }
                p += 1
            }
            i += best
        } else {
            comp[csize] = 0
            comp[csize + 1] = data[i]
            csize += 2
            i += 1
        }
    }

    while i < n {
        comp[csize] = 0
        comp[csize + 1] = data[i]
        csize += 2
        i += 1
    }

    // ---- decompress and verify ----
    var out = [UInt8](repeating: 0, count: n)
    var o = 0
    var c = 0
    while c < csize {
        if comp[c] == 0 {
            out[o] = comp[c + 1]
            o += 1
            c += 2
        } else {
            let len = Int(comp[c + 1]) + MIN_MATCH
            let back = Int(comp[c + 2]) + Int(comp[c + 3]) * 256 + 1
            for _ in 0..<len {
                out[o] = out[o - back]
                o += 1
            }
            c += 4
        }
    }

    var same = o == n
    var k = 0
    while same && k < n {
        if out[k] != data[k] {
            same = false
        }
        k += 1
    }

    var hc: UInt64 = 0
    for k in 0..<csize {
        hc = (hc &* 31 &+ UInt64(comp[k])) % 1000003
    }

    let check: UInt64 = same ? UInt64(csize) &* 1000003 &+ hc : 0

    let t1 = now()
    print(String(format: "CHECK=%llu MS=%.6f", check, (t1 - t0) * 1000.0))
}

runMain()
