using System;
using System.Diagnostics;

static class Bench
{
    const int N = 300000;

    static ulong gSeed = 12345;

    static ulong Rnd()
    {
        gSeed = (gSeed * 16807) % 2147483647;
        return gSeed;
    }

    static void Swap(ulong[] a, int i, int j)
    {
        ulong t = a[i];
        a[i] = a[j];
        a[j] = t;
    }

    static void QSort(ulong[] a, int lo, int hi)
    {
        while (hi - lo > 16)
        {
            int mid = lo + (hi - lo) / 2;
            if (a[mid] < a[lo])
                Swap(a, lo, mid);
            if (a[hi] < a[lo])
                Swap(a, lo, hi);
            if (a[hi] < a[mid])
                Swap(a, mid, hi);

            ulong pivot = a[mid];
            int i = lo;
            int j = hi;
            do
            {
                while (a[i] < pivot)
                    i += 1;
                while (a[j] > pivot)
                    j -= 1;
                if (i <= j)
                {
                    Swap(a, i, j);
                    i += 1;
                    j -= 1;
                }
            } while (i <= j);

            // Recurse into the smaller side, loop on the larger one.
            if (j - lo < hi - i)
            {
                QSort(a, lo, j);
                lo = i;
            }
            else
            {
                QSort(a, i, hi);
                hi = j;
            }
        }

        for (int i = lo + 1; i <= hi; i++)
        {
            ulong v = a[i];
            int j = i - 1;
            while (j >= lo && a[j] > v)
            {
                a[j + 1] = a[j];
                j -= 1;
            }
            a[j + 1] = v;
        }
    }

    static int Main()
    {
        // ---- data generation (not timed) ----
        var a = new ulong[N];
        for (int i = 0; i < N; i++)
            a[i] = Rnd();

        // ---- timed work ----
        long start_t = Stopwatch.GetTimestamp();

        QSort(a, 0, N - 1);

        bool sorted = true;
        for (int i = 1; i < N; i++)
        {
            if (a[i - 1] > a[i])
                sorted = false;
        }

        ulong check = 0;
        if (sorted)
        {
            for (int i = 0; i < N; i++)
                check += (a[i] % 1000) * (ulong) (i % 7 + 1);
        }

        double ms = (Stopwatch.GetTimestamp() - start_t) * 1000.0 / Stopwatch.Frequency;
        Console.WriteLine($"CHECK={check} MS={ms:F6}");
        return 0;
    }
}
