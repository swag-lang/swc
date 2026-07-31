import WinSDK
import Foundation

let N = 800
let NN = N * N
let INF: UInt64 = 0x0FFFFFFFFFFFFFFF

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

// Binary heap kept in a local struct rather than in globals: same shape as the
// Rust port, and top-level `var`s in main.swift are globals the optimiser cannot
// prove unique.
struct Heap {
    var d: [UInt64]
    var n: [Int]
    var size: Int

    init(_ capacity: Int) {
        d = [UInt64](repeating: 0, count: capacity)
        n = [Int](repeating: 0, count: capacity)
        size = 0
    }

    mutating func push(_ dist: UInt64, _ node: Int) {
        var i = size
        size += 1
        d[i] = dist
        n[i] = node

        while i > 0 {
            let p = (i - 1) >> 1
            if d[p] <= d[i] {
                break
            }
            d.swapAt(p, i)
            n.swapAt(p, i)
            i = p
        }
    }

    mutating func pop() -> (UInt64, Int) {
        let popD = d[0]
        let popN = n[0]
        size -= 1
        d[0] = d[size]
        n[0] = n[size]

        var i = 0
        while true {
            let l = 2 * i + 1
            if l >= size {
                break
            }
            let r = l + 1
            var m = l
            if r < size && d[r] < d[l] {
                m = r
            }
            if d[i] <= d[m] {
                break
            }
            d.swapAt(m, i)
            n.swapAt(m, i)
            i = m
        }

        return (popD, popN)
    }
}

func runMain() {
    // ---- data generation (not timed) ----
    var weight = [UInt64](repeating: 0, count: NN)
    for i in 0..<NN {
        weight[i] = 1 &+ (rnd() % 9)
    }

    // ---- timed work ----
    let t0 = now()

    var dist = [UInt64](repeating: INF, count: NN)
    var heap = Heap(NN * 4)

    dist[0] = 0
    heap.push(0, 0)

    var pops: UInt64 = 0
    let target = NN - 1

    while heap.size > 0 {
        let (d, u) = heap.pop()
        pops += 1
        if d > dist[u] {
            continue
        }
        if u == target {
            break
        }

        let x = u % N
        let y = u / N

        if x > 0 {
            let v = u - 1
            let nd = d &+ weight[v]
            if nd < dist[v] {
                dist[v] = nd
                heap.push(nd, v)
            }
        }
        if x < N - 1 {
            let v = u + 1
            let nd = d &+ weight[v]
            if nd < dist[v] {
                dist[v] = nd
                heap.push(nd, v)
            }
        }
        if y > 0 {
            let v = u - N
            let nd = d &+ weight[v]
            if nd < dist[v] {
                dist[v] = nd
                heap.push(nd, v)
            }
        }
        if y < N - 1 {
            let v = u + N
            let nd = d &+ weight[v]
            if nd < dist[v] {
                dist[v] = nd
                heap.push(nd, v)
            }
        }
    }

    let check = dist[target] &* 1000 &+ (pops % 1000)

    let t1 = now()
    print(String(format: "CHECK=%llu MS=%.6f", check, (t1 - t0) * 1000.0))
}

runMain()
