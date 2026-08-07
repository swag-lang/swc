import WinSDK
import Foundation

let NWORDS = 4194304 // 32-bit words, sixteen mebibytes of key stream
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

@inline(__always)
func add32(_ left: UInt32, _ right: UInt32) -> UInt32 {
    return UInt32((UInt64(left) + UInt64(right)) & M32)
}

@inline(__always)
func rol(_ x: UInt32, _ k: UInt32) -> UInt32 {
    return (x &<< k) | (x &>> (32 - k))
}

@inline(__always)
func quarterRound(_ state: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
    state[a] = add32(state[a], state[b])
    state[d] ^= state[a]
    state[d] = rol(state[d], 16)
    state[c] = add32(state[c], state[d])
    state[b] ^= state[c]
    state[b] = rol(state[b], 12)
    state[a] = add32(state[a], state[b])
    state[d] ^= state[a]
    state[d] = rol(state[d], 8)
    state[c] = add32(state[c], state[d])
    state[b] ^= state[c]
    state[b] = rol(state[b], 7)
}

func runMain() {
    // ---- data generation (not timed) ----
    var data = [UInt32](repeating: 0, count: NWORDS)
    for i in 0..<NWORDS {
        data[i] = UInt32(rnd() & M32)
    }

    var key = [UInt32](repeating: 0, count: 8)
    for i in 0..<8 {
        key[i] = UInt32(rnd() & M32)
    }

    var nonce = [UInt32](repeating: 0, count: 3)
    for i in 0..<3 {
        nonce[i] = UInt32(rnd() & M32)
    }

    // ---- timed work ----
    let t0 = now()

    var initial = [UInt32](repeating: 0, count: 16)
    initial[0] = 0x61707865
    initial[1] = 0x3320646E
    initial[2] = 0x79622D32
    initial[3] = 0x6B206574
    for i in 0..<8 {
        initial[4 + i] = key[i]
    }
    for i in 0..<3 {
        initial[13 + i] = nonce[i]
    }

    var offset = 0
    var counter: UInt32 = 1
    var state = [UInt32](repeating: 0, count: 16)
    while offset < NWORDS {
        initial[12] = counter

        for i in 0..<16 {
            state[i] = initial[i]
        }

        for _ in 0..<10 {
            quarterRound(&state, 0, 4, 8, 12)
            quarterRound(&state, 1, 5, 9, 13)
            quarterRound(&state, 2, 6, 10, 14)
            quarterRound(&state, 3, 7, 11, 15)
            quarterRound(&state, 0, 5, 10, 15)
            quarterRound(&state, 1, 6, 11, 12)
            quarterRound(&state, 2, 7, 8, 13)
            quarterRound(&state, 3, 4, 9, 14)
        }

        for i in 0..<16 {
            data[offset + i] ^= add32(state[i], initial[i])
        }

        offset += 16
        counter = counter &+ 1
    }

    var check: UInt64 = 0
    for i in 0..<NWORDS {
        check ^= (UInt64(data[i]) + UInt64(i)) & M32
    }

    let t1 = now()
    print(String(format: "CHECK=%llu MS=%.6f", check, (t1 - t0) * 1000.0))
}

runMain()
