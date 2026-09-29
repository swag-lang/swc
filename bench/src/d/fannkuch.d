module fannkuch;

import common;

immutable s64 N = 9;

int main()
{
    s64* perm  = cast(s64*) xalloc(N * s64.sizeof);
    s64* perm1 = cast(s64*) xalloc(N * s64.sizeof);
    s64* count = cast(s64*) xalloc(N * s64.sizeof);

    // Timed work starts after data generation.
    double t0 = now();

    for (s64 i = 0; i < N; i++)
        perm1[i] = i;

    s64 checksum  = 0;
    s64 maxFlips  = 0;
    s64 permCount = 0;
    s64 r         = N;

    while (true)
    {
        while (r != 1)
        {
            count[r - 1] = r;
            r -= 1;
        }

        for (s64 i = 0; i < N; i++)
            perm[i] = perm1[i];

        s64 flips = 0;
        s64 k     = perm[0];
        while (k != 0)
        {
            s64 i = 0;
            s64 j = k;
            while (i < j)
            {
                s64 t   = perm[i];
                perm[i] = perm[j];
                perm[j] = t;
                i += 1;
                j -= 1;
            }
            flips += 1;
            k = perm[0];
        }

        if (flips > maxFlips)
            maxFlips = flips;
        if (permCount % 2 == 0)
            checksum += flips;
        else
            checksum -= flips;

        // Rotate the prefix to reach the next permutation.
        bool done = false;
        while (true)
        {
            if (r == N)
            {
                done = true;
                break;
            }
            s64 perm0 = perm1[0];
            for (s64 i = 0; i < r; i++)
                perm1[i] = perm1[i + 1];
            perm1[r] = perm0;
            count[r] -= 1;
            if (count[r] > 0)
                break;
            r += 1;
        }
        if (done)
            break;
        permCount += 1;
    }

    u64 check = cast(u64) (checksum * 1000 + maxFlips);

    double t1 = now();
    report(check, t0, t1);

    free(count);
    free(perm1);
    free(perm);
    return 0;
}
