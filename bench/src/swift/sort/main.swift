import WinSDK
import Foundation

let N = 300000

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

func qsort(_ a: inout [UInt64], _ loIn: Int, _ hiIn: Int) {
    var lo = loIn
    var hi = hiIn
    while hi - lo > 16 {
        let mid = lo + (hi - lo) / 2
        if a[mid] < a[lo] {
            a.swapAt(lo, mid)
        }
        if a[hi] < a[lo] {
            a.swapAt(lo, hi)
        }
        if a[hi] < a[mid] {
            a.swapAt(mid, hi)
        }

        let pivot = a[mid]
        var i = lo
        var j = hi
        repeat {
            while a[i] < pivot {
                i += 1
            }
            while a[j] > pivot {
                j -= 1
            }
            if i <= j {
                a.swapAt(i, j)
                i += 1
                j -= 1
            }
        } while i <= j

        // Recurse into the smaller side, loop on the larger one.
        if j - lo < hi - i {
            qsort(&a, lo, j)
            lo = i
        } else {
            qsort(&a, i, hi)
            hi = j
        }
    }

    var i = lo + 1
    while i <= hi {
        let v = a[i]
        var j = i - 1
        while j >= lo && a[j] > v {
            a[j + 1] = a[j]
            j -= 1
        }
        a[j + 1] = v
        i += 1
    }
}

func runMain() {
    // ---- data generation (not timed) ----
    var a = [UInt64](repeating: 0, count: N)
    for i in 0..<N {
        a[i] = rnd()
    }

    // ---- timed work ----
    let t0 = now()

    qsort(&a, 0, N - 1)

    var sorted = true
    for i in 1..<N {
        if a[i - 1] > a[i] {
            sorted = false
        }
    }

    var check: UInt64 = 0
    if sorted {
        for i in 0..<N {
            check &+= (a[i] % 1000) &* UInt64(i % 7 + 1)
        }
    }

    let t1 = now()
    print(String(format: "CHECK=%llu MS=%.6f", check, (t1 - t0) * 1000.0))
}

runMain()
