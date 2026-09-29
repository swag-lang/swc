package main

import common "common"

N :: i64(9)

main :: proc() {
    perm: [^]i64 = ([^]i64)(common.xalloc(u64(N * size_of(i64))))
    perm1: [^]i64 = ([^]i64)(common.xalloc(u64(N * size_of(i64))))
    count: [^]i64 = ([^]i64)(common.xalloc(u64(N * size_of(i64))))
    // Timed work starts after data generation.
    t0: f64 = common.now()
    for i: i64 = 0; (i < N); i += 1 {
        perm1[i] = i
    }
    checksum: i64 = 0
    maxFlips: i64 = 0
    permCount: i64 = 0
    r: i64 = N
    for true {
        for (r != 1) {
            count[r - 1] = r
            r -= 1
        }
        for i: i64 = 0; (i < N); i += 1 {
            perm[i] = perm1[i]
        }
        flips: i64 = 0
        k: i64 = perm[0]
        for (k != 0) {
            i: i64 = 0
            j: i64 = k
            for (i < j) {
                t: i64 = perm[i]
                perm[i] = perm[j]
                perm[j] = t
                i += 1
                j -= 1
            }
            flips += 1
            k = perm[0]
        }
        if (flips > maxFlips) {
            maxFlips = flips
        }
        if ((permCount % 2) == 0) {
            checksum += flips
        } else {
            checksum -= flips
        }
        // Rotate the prefix to reach the next permutation.
        done: bool = false
        for true {
            if (r == N) {
                done = true
                break
            }
            perm0: i64 = perm1[0]
            for i: i64 = 0; (i < r); i += 1 {
                perm1[i] = perm1[i + 1]
            }
            perm1[r] = perm0
            count[r] -= 1
            if (count[r] > 0) {
                break
            }
            r += 1
        }
        if (done) {
            break
        }
        permCount += 1
    }
    check: u64 = u64(((checksum * 1000) + maxFlips))
    t1: f64 = common.now()
    common.report(check, t0, t1)
    common.free(count)
    common.free(perm1)
    common.free(perm)
    return
}
