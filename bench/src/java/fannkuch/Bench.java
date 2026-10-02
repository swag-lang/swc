class Bench
{
    static final int N = 9;

    public static void main(String[] args)
    {
        // ---- data generation (not timed) ----
        var perm = new int[N];
        var perm1 = new int[N];
        var count = new int[N];

        // ---- timed work ----
        long startTime = System.nanoTime();

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
                count[(int) (r - 1)] = r;
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
            boolean done = false;
            while (true)
            {
                if (r == N)
                {
                    done = true;
                    break;
                }
                int perm0 = perm1[0];
                for (int i = 0; i < r; i++)
                    perm1[i] = perm1[(int) (i + 1)];
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

        long check = (long) (checksum * 1000 + maxFlips);

        double ms = (System.nanoTime() - startTime) * 1000.0 / 1_000_000_000.0;
        System.out.printf(java.util.Locale.ROOT, "CHECK=%d MS=%.6f%n", check, ms);
        return;
    }
}
