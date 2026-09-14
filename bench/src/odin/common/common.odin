package common

import "core:c/libc"
import "core:math"
import "core:sys/windows"

free :: libc.free
memcmp :: libc.memcmp
memcpy :: libc.memcpy
memset :: libc.memset
strlen :: libc.strlen
sqrt :: math.sqrt

seed: u64 = 12345

rnd :: proc() -> u64 {
    seed = (seed * 16807) % 2147483647
    return seed
}

now :: proc() -> f64 {
    counter, frequency: i64
    windows.QueryPerformanceCounter(&counter)
    windows.QueryPerformanceFrequency(&frequency)
    return f64(counter) / f64(frequency)
}

report :: proc(check: u64, t0, t1: f64) {
    libc.printf("CHECK=%llu MS=%.6f\n", check, (t1 - t0) * 1000.0)
}

xalloc :: proc(n: u64) -> rawptr {
    p := libc.malloc(uint(n))
    if p == nil {
        libc.exit(1)
    }
    return p
}
