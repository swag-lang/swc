package common

import "core:c/libc"
import "core:math"
import "core:sys/windows"

free :: libc.free
sqrt :: math.sqrt

memcmp :: proc(left, right: rawptr, n: u64) -> i32 {
    return libc.memcmp(left, right, uint(n))
}

memcpy :: proc(dst, src: rawptr, n: u64) {
    libc.memcpy(dst, src, uint(n))
}

memset :: proc(dst: rawptr, value: i32, n: u64) {
    libc.memset(dst, value, uint(n))
}

strlen :: proc(text: cstring) -> u64 {
    return u64(libc.strlen(text))
}

seed: u64 = 12345

rnd :: proc() -> u64 {
    seed = (seed * 16807) % 2147483647
    return seed
}

now :: proc() -> f64 {
    counter, frequency: windows.LARGE_INTEGER
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
