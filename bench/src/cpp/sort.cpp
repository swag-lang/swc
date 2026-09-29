#include "common.h"

static const s64 N = 300000;

static inline void swap(u64* a, s64 i, s64 j)
{
    u64 t = a[i];
    a[i]  = a[j];
    a[j]  = t;
}

static void qsort(u64* a, s64 lo, s64 hi)
{
    while (hi - lo > 16)
    {
        s64 mid = lo + (hi - lo) / 2;
        if (a[mid] < a[lo])
            swap(a, lo, mid);
        if (a[hi] < a[lo])
            swap(a, lo, hi);
        if (a[hi] < a[mid])
            swap(a, mid, hi);

        u64 pivot = a[mid];
        s64 i     = lo;
        s64 j     = hi;
        do
        {
            while (a[i] < pivot)
                i += 1;
            while (a[j] > pivot)
                j -= 1;
            if (i <= j)
            {
                swap(a, i, j);
                i += 1;
                j -= 1;
            }
        } while (i <= j);

        // Recurse into the smaller side, loop on the larger one.
        if (j - lo < hi - i)
        {
            qsort(a, lo, j);
            lo = i;
        }
        else
        {
            qsort(a, i, hi);
            hi = j;
        }
    }

    for (s64 i = lo + 1; i <= hi; i++)
    {
        u64 v = a[i];
        s64 j = i - 1;
        while (j >= lo && a[j] > v)
        {
            a[j + 1] = a[j];
            j -= 1;
        }
        a[j + 1] = v;
    }
}

int main()
{
    // ---- data generation (not timed) ----
    u64* a = (u64*) xalloc(N * sizeof(u64));
    for (s64 i = 0; i < N; i++)
        a[i] = rnd();

    // ---- timed work ----
    double t0 = now();

    qsort(a, 0, N - 1);

    bool sorted = true;
    for (s64 i = 1; i < N; i++)
    {
        if (a[i - 1] > a[i])
            sorted = false;
    }

    u64 check = 0;
    if (sorted)
    {
        for (s64 i = 0; i < N; i++)
            check += (a[i] % 1000) * (u64) (i % 7 + 1);
    }

    double t1 = now();
    report(check, t0, t1);

    free(a);
    return 0;
}
