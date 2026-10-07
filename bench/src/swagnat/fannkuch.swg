const N = 9's64

#main
{
    // ---- data generation (not timed) ----
    let perm  = cast([*] s64, (benchAlloc(N * #sizeof(s64)))!)
    let perm1 = cast([*] s64, (benchAlloc(N * #sizeof(s64)))!)
    let count = cast([*] s64, (benchAlloc(N * #sizeof(s64)))!)

    // ---- timed work ----
    let t0 = now()

    for i in N do
        perm1[i] = i

    var checksum  = 0's64
    var maxFlips  = 0's64
    var permCount = 0's64
    var r         = N

    while true
    {
        while r != 1
        {
            count[r - 1] = r
            r -= 1
        }

        for i in N do
            perm[i] = perm1[i]

        var flips = 0's64
        var k     = perm[0]
        while k != 0
        {
            var i = 0's64
            var j = k
            while i < j
            {
                let t = perm[i]
                perm[i] = perm[j]
                perm[j] = t
                i       += 1
                j       -= 1
            }

            flips += 1
            k     = perm[0]
        }

        if flips > maxFlips do
            maxFlips = flips
        if permCount % 2 == 0 do
            checksum += flips
        else do
            checksum -= flips

        // Rotate the prefix to reach the next permutation.
        var done = false
        while true
        {
            if r == N
            {
                done = true
                break
            }

            let perm0 = perm1[0]
            for i in r do
                perm1[i] = perm1[i + 1]
            perm1[r] = perm0
            count[r] -= 1
            if count[r] > 0 do
                break
            r += 1
        }

        if done do
            break
        permCount += 1
    }

    let check = cast(u64, (checksum * 1000 + maxFlips))

    let t1 = now()
    report(check, t0, t1)

    benchFree(count)
    benchFree(perm1)
    benchFree(perm)
}
