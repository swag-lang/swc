import WinSDK
import Foundation

let N = 9

func now() -> Double {
    var c = LARGE_INTEGER()
    var f = LARGE_INTEGER()
    QueryPerformanceCounter(&c)
    QueryPerformanceFrequency(&f)
    return Double(c.QuadPart) / Double(f.QuadPart)
}

func runMain() {
    // ---- data generation (not timed) ----
    var perm = [Int](repeating: 0, count: N)
    var perm1 = [Int](repeating: 0, count: N)
    var count = [Int](repeating: 0, count: N)

    // ---- timed work ----
    let t0 = now()

    for i in 0..<N {
        perm1[i] = i
    }

    var checksum = 0
    var maxFlips = 0
    var permCount = 0
    var r = N

    while true {
        while r != 1 {
            count[r - 1] = r
            r -= 1
        }

        for i in 0..<N {
            perm[i] = perm1[i]
        }

        var flips = 0
        var k = perm[0]
        while k != 0 {
            var i = 0
            var j = k
            while i < j {
                perm.swapAt(i, j)
                i += 1
                j -= 1
            }
            flips += 1
            k = perm[0]
        }

        if flips > maxFlips {
            maxFlips = flips
        }
        if permCount % 2 == 0 {
            checksum += flips
        } else {
            checksum -= flips
        }

        // Rotate the prefix to reach the next permutation.
        var done = false
        while true {
            if r == N {
                done = true
                break
            }
            let perm0 = perm1[0]
            for i in 0..<r {
                perm1[i] = perm1[i + 1]
            }
            perm1[r] = perm0
            count[r] -= 1
            if count[r] > 0 {
                break
            }
            r += 1
        }
        if done {
            break
        }
        permCount += 1
    }

    let check = UInt64(checksum * 1000 + maxFlips)

    let t1 = now()
    print(String(format: "CHECK=%llu MS=%.6f", check, (t1 - t0) * 1000.0))
}

runMain()
