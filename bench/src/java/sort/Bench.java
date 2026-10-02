class Bench
{
    static final int N = 300000;

    static long gSeed = 12345;

    static long rnd()
    {
        gSeed = (gSeed * 16807) % 2147483647;
        return gSeed;
    }

    static void swap(long[] a, int i, int j)
    {
        long t = a[i];
        a[i] = a[j];
        a[j] = t;
    }

    static void qSort(long[] a, int lo, int hi)
    {
        while (hi - lo > 16)
        {
            int mid = lo + (hi - lo) / 2;
            if (a[mid] < a[lo])
                swap(a, lo, mid);
            if (a[hi] < a[lo])
                swap(a, lo, hi);
            if (a[hi] < a[mid])
                swap(a, mid, hi);

            long pivot = a[mid];
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
                    swap(a, i, j);
                    i += 1;
                    j -= 1;
                }
            } while (i <= j);

            // Recurse into the smaller side, loop on the larger one.
            if (j - lo < hi - i)
            {
                qSort(a, lo, j);
                lo = i;
            }
            else
            {
                qSort(a, i, hi);
                hi = j;
            }
        }

        for (int i = lo + 1; i <= hi; i++)
        {
            long v = a[i];
            int j = i - 1;
            while (j >= lo && a[j] > v)
            {
                a[(int) (j + 1)] = a[j];
                j -= 1;
            }
            a[(int) (j + 1)] = v;
        }
    }

    public static void main(String[] args)
    {
        // ---- data generation (not timed) ----
        var a = new long[N];
        for (int i = 0; i < N; i++)
            a[i] = rnd();

        // ---- timed work ----
        long startTime = System.nanoTime();

        qSort(a, 0, N - 1);

        boolean sorted = true;
        for (int i = 1; i < N; i++)
        {
            if (a[(int) (i - 1)] > a[i])
                sorted = false;
        }

        long check = 0;
        if (sorted)
        {
            for (int i = 0; i < N; i++)
                check += (a[i] % 1000) * (long) (i % 7 + 1);
        }

        double ms = (System.nanoTime() - startTime) * 1000.0 / 1_000_000_000.0;
        System.out.printf(java.util.Locale.ROOT, "CHECK=%d MS=%.6f%n", check, ms);
        return;
    }
}
