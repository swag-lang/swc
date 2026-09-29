package main

import common "common"

N :: i64(300000)

swap :: proc(a: [^]u64, i: i64, j: i64) {
    t: u64 = a[i]
    a[i] = a[j]
    a[j] = t
}

qsort :: proc(a: [^]u64, lo_in: i64, hi_in: i64) {
    lo: i64 = lo_in
    hi: i64 = hi_in
    for ((hi - lo) > 16) {
        mid: i64 = (lo + ((hi - lo) / 2))
        if (a[mid] < a[lo]) {
            swap(a, lo, mid)
        }
        if (a[hi] < a[lo]) {
            swap(a, lo, hi)
        }
        if (a[hi] < a[mid]) {
            swap(a, mid, hi)
        }
        pivot: u64 = a[mid]
        i: i64 = lo
        j: i64 = hi
        for {
            for (a[i] < pivot) {
                i += 1
            }
            for (a[j] > pivot) {
                j -= 1
            }
            if (i <= j) {
                swap(a, i, j)
                i += 1
                j -= 1
            }
            if (i > j) {
                break
            }
        }
        // Recurse into the smaller side, loop on the larger one.
        if ((j - lo) < (hi - i)) {
            qsort(a, lo, j)
            lo = i
        } else {
            qsort(a, i, hi)
            hi = j
        }
    }
    for i: i64 = (lo + 1); (i <= hi); i += 1 {
        v: u64 = a[i]
        j: i64 = (i - 1)
        for ((j >= lo) && (a[j] > v)) {
            a[j + 1] = a[j]
            j -= 1
        }
        a[j + 1] = v
    }
}

main :: proc() {
    a: [^]u64 = ([^]u64)(common.xalloc(u64(N * size_of(u64))))
    for i: i64 = 0; (i < N); i += 1 {
        a[i] = common.rnd()
    }
    // Timed work starts after data generation.
    t0: f64 = common.now()
    qsort(a, 0, (N - 1))
    sorted: bool = true
    for i: i64 = 1; (i < N); i += 1 {
        if (a[i - 1] > a[i]) {
            sorted = false
        }
    }
    check: u64 = 0
    if (sorted) {
        for i: i64 = 0; (i < N); i += 1 {
            check += ((a[i] % 1000) * u64(((i % 7) + 1)))
        }
    }
    t1: f64 = common.now()
    common.report(check, t0, t1)
    common.free(a)
    return
}
