const N = 300000's64

func swap(a: [*] u64, i, j: s64)
{
    let t = a[i]
    a[i] = a[j]
    a[j] = t
}

func qsort(a: [*] u64, first, last: s64)
{
    var lo = first
    var hi = last
    while hi - lo > 16
    {
        let mid = lo + (hi - lo) / 2
        if a[mid] < a[lo] do
            swap(a, lo, mid)
        if a[hi] < a[lo] do
            swap(a, lo, hi)
        if a[hi] < a[mid] do
            swap(a, mid, hi)

        let pivot = a[mid]
        var i     = lo
        var j     = hi
        while true
        {
            while a[i] < pivot do
                i += 1
            while a[j] > pivot do
                j -= 1
            if i <= j
            {
                swap(a, i, j)
                i += 1
                j -= 1
            }

            if i > j do
                break
        }

        // Recurse into the smaller side, loop on the larger one.
        if j - lo < hi - i
        {
            qsort(a, lo, j)
            lo = i
        }
        else
        {
            qsort(a, i, hi)
            hi = j
        }
    }

    // The range can be empty or inverted, which a `for` range rejects.
    var i = lo + 1
    while i <= hi
    {
        let v = a[i]
        var j = i - 1
        while j >= lo and a[j] > v
        {
            a[j + 1] = a[j]
            j        -= 1
        }

        a[j + 1] = v
        i        += 1
    }
}

#run
{
    // ---- data generation (not timed) ----
    let a = cast([*] u64, (benchAlloc(cast(u64, N) * #sizeof(u64)))!)
    for i in N do
        a[i] = rnd()

    // ---- timed work ----
    let t0 = now()

    qsort(a, 0, N - 1)

    var sorted = true
    for i in 1 until N
    {
        if a[i - 1] > a[i] do
            sorted = false
    }

    var check = 0'u64
    if sorted
    {
        for i in N do
            check += (a[i] % 1000) * cast(u64, (i % 7 + 1))
    }

    let t1 = now()
    report(check, t0, t1)

    benchFree(a)
}
