using System;
using System.Diagnostics;

static class Bench
{
    const int N = 9;

    static int Main()
    {
        // ---- data generation (not timed) ----
        var perm = new int[N];
        var perm1 = new int[N];
        var count = new int[N];

        // ---- timed work ----
        long start_t = Stopwatch.GetTimestamp();

        for (int i = 0; i < N; i++)
            perm1[i] = i;

        long checksum = 0;
        long maxFlips = 0;
        long permCount = 0;
        int r = N;

        while (true)
        {
            while (r != 1)
            {
                count[r - 1] = r;
                r -= 1;
            }

            for (int i = 0; i < N; i++)
                perm[i] = perm1[i];

            long flips = 0;
            int k = perm[0];
            while (k != 0)
            {
                int i = 0;
                int j = k;
                while (i < j)
                {
                    int t = perm[i];
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
                int perm0 = perm1[0];
                for (int i = 0; i < r; i++)
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

        ulong check = (ulong) (checksum * 1000 + maxFlips);

        double ms = (Stopwatch.GetTimestamp() - start_t) * 1000.0 / Stopwatch.Frequency;
        Console.WriteLine($"CHECK={check} MS={ms:F6}");
        return 0;
    }
}
