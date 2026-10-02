class Bench
{
    static final long DICT = 6000;
    static final long QUERIES = 40;
    static final long MAXLEN = 3;

    static long gSeed = 12345;

    static long rnd()
    {
        gSeed = (gSeed * 16807) % 2147483647;
        return gSeed;
    }

    public static void main(String[] args)
    {
        // ---- data generation (not timed) ----
        var bytes = new byte[(int) (DICT * 16)];
        var wordOff = new long[(int) (DICT)];
        var wordLen = new long[(int) (DICT)];

        long wp = 0;
        for (long i = 0; i < DICT; i++)
        {
            long n = i + 1;
            long l = 4 + (i % 7);
            wordOff[(int) i] = wp;
            wordLen[(int) i] = l;
            for (long k = 0; k < l; k++)
            {
                bytes[(int) wp] = (byte) (97 + (n % 26));
                wp += 1;
                n = n / 26 + 7 * k;
            }
        }

        var qBytes = new byte[(int) (QUERIES * 32)];
        var qOff = new long[(int) (QUERIES)];
        var qLen = new long[(int) (QUERIES)];

        long qp = 0;
        for (int q = 0; q < (int) QUERIES; q++)
        {
            var tmp = new byte[32];
            long src = rnd() % DICT;
            long nw = wordLen[(int) src];
            for (int i = 0; i < (int) nw; i++)
                tmp[(int) (i)] = bytes[(int) wordOff[(int) src] + i];

            for (int rep = 0; rep < 2; rep++)
            {
                long p = rnd() % nw;
                long op = rnd() % 3;
                byte c = (byte) (97 + (rnd() % 26));
                if (op == 0)
                {
                    tmp[(int) p] = c;
                }
                else if (op == 1)
                {
                    if (nw > 2)
                    {
                        long i = p;
                        while (i + 1 < nw)
                        {
                            tmp[(int) i] = tmp[(int) (i + 1)];
                            i += 1;
                        }
                        nw -= 1;
                    }
                }
                else
                {
                    long i = nw;
                    while (i > p)
                    {
                        tmp[(int) i] = tmp[(int) (i - 1)];
                        i -= 1;
                    }
                    tmp[(int) p] = c;
                    nw += 1;
                }
            }

            qOff[q] = qp;
            qLen[q] = nw;
            for (int i = 0; i < (int) nw; i++)
            {
                qBytes[(int) qp] = tmp[(int) (i)];
                qp += 1;
            }
        }

        // ---- timed work ----
        long startTime = System.nanoTime();

        var row0 = new long[64];
        var row1 = new long[64];

        long check = 0;
        for (int q = 0; q < (int) QUERIES; q++)
        {
            long ao = qOff[q];
            long la = qLen[q];
            long best = 1073741824;
            long bestIdx = -1;

            for (int i = 0; i < (int) DICT; i++)
            {
                long bo = wordOff[(int) (i)];
                long lb = wordLen[(int) (i)];
                long d = la > lb ? la - lb : lb - la;
                if (d > MAXLEN)
                    continue;

                for (int j = 0; j < (int) lb + 1; j++)
                    row0[j] = (long) j;

                for (long x = 0; x < la; x++)
                {
                    row1[0] = x + 1;
                    byte ca = qBytes[(int) (ao + x)];
                    for (int y = 0; y < (int) lb; y++)
                    {
                        long cost = ca == bytes[(int) bo + y] ? 0L : 1L;
                        long v = row0[y] + cost;
                        long v2 = row0[(int) (y + 1)] + 1;
                        if (v2 < v)
                            v = v2;
                        v2 = row1[y] + 1;
                        if (v2 < v)
                            v = v2;
                        row1[(int) (y + 1)] = v;
                    }
                    for (int j = 0; j < (int) lb + 1; j++)
                        row0[j] = row1[j];
                }

                long dd = row0[(int) lb];
                if (dd < best)
                {
                    best = dd;
                    bestIdx = i;
                }
            }

            check += (long) best * 31 + bestIdx;
        }

        double ms = (System.nanoTime() - startTime) * 1000.0 / 1_000_000_000.0;
        System.out.printf(java.util.Locale.ROOT, "CHECK=%d MS=%.6f%n", (long) check, ms);
        return;
    }
}
