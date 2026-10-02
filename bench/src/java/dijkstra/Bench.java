class Bench
{
    static final long N = 800;
    static final long NN = N * N;
    static final long INF = 0x0FFFFFFFFFFFFFFFL;

    static long gSeed = 12345;

    static long rnd()
    {
        gSeed = (gSeed * 16807) % 2147483647;
        return gSeed;
    }

    static long[] gHeapD;
    static long[] gHeapN;
    static long gHeapSize = 0;

    static long gPopD = 0;
    static long gPopN = 0;

    static void push(long d, long node)
    {
        long i = gHeapSize;
        gHeapSize += 1;
        gHeapD[(int) i] = d;
        gHeapN[(int) i] = node;

        while (i > 0)
        {
            long p = (i - 1) >> 1;
            if (gHeapD[(int) p] <= gHeapD[(int) i])
                break;
            long td = gHeapD[(int) p];
            gHeapD[(int) p] = gHeapD[(int) i];
            gHeapD[(int) i] = td;
            long tn = gHeapN[(int) p];
            gHeapN[(int) p] = gHeapN[(int) i];
            gHeapN[(int) i] = tn;
            i = p;
        }
    }

    static void pop()
    {
        gPopD = gHeapD[0];
        gPopN = gHeapN[0];
        gHeapSize -= 1;
        gHeapD[0] = gHeapD[(int) gHeapSize];
        gHeapN[0] = gHeapN[(int) gHeapSize];

        long i = 0;
        while (true)
        {
            long l = 2 * i + 1;
            if (l >= gHeapSize)
                break;
            long r = l + 1;
            long m = l;
            if (r < gHeapSize && gHeapD[(int) r] < gHeapD[(int) l])
                m = r;
            if (gHeapD[(int) i] <= gHeapD[(int) m])
                break;
            long td = gHeapD[(int) m];
            gHeapD[(int) m] = gHeapD[(int) i];
            gHeapD[(int) i] = td;
            long tn = gHeapN[(int) m];
            gHeapN[(int) m] = gHeapN[(int) i];
            gHeapN[(int) i] = tn;
            i = m;
        }
    }

    public static void main(String[] args)
    {
        // ---- data generation (not timed) ----
        var weight = new long[(int) (NN)];
        for (int i = 0; i < (int) NN; i++)
            weight[(int) (i)] = 1 + (rnd() % 9);

        // ---- timed work ----
        long startTime = System.nanoTime();

        var dist = new long[(int) (NN)];
        for (int i = 0; i < (int) NN; i++)
            dist[(int) (i)] = INF;

        gHeapD = new long[(int) (NN * 4)];
        gHeapN = new long[(int) (NN * 4)];
        gHeapSize = 0;

        dist[0] = 0;
        push(0, 0);

        long pops = 0;
        final long Target = NN - 1;

        while (gHeapSize > 0)
        {
            pop();
            long d = gPopD;
            long u = gPopN;
            pops += 1;
            if (d > dist[(int) u])
                continue;
            if (u == Target)
                break;

            long x = u % N;
            long y = u / N;

            if (x > 0)
            {
                long v = u - 1;
                long nd = d + weight[(int) v];
                if (nd < dist[(int) v])
                {
                    dist[(int) v] = nd;
                    push(nd, v);
                }
            }
            if (x < N - 1)
            {
                long v = u + 1;
                long nd = d + weight[(int) v];
                if (nd < dist[(int) v])
                {
                    dist[(int) v] = nd;
                    push(nd, v);
                }
            }
            if (y > 0)
            {
                long v = u - N;
                long nd = d + weight[(int) v];
                if (nd < dist[(int) v])
                {
                    dist[(int) v] = nd;
                    push(nd, v);
                }
            }
            if (y < N - 1)
            {
                long v = u + N;
                long nd = d + weight[(int) v];
                if (nd < dist[(int) v])
                {
                    dist[(int) v] = nd;
                    push(nd, v);
                }
            }
        }

        long check = dist[(int) Target] * 1000 + (pops % 1000);

        double ms = (System.nanoTime() - startTime) * 1000.0 / 1_000_000_000.0;
        System.out.printf(java.util.Locale.ROOT, "CHECK=%d MS=%.6f%n", check, ms);
        return;
    }
}
