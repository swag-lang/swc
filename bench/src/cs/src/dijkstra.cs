using System;
using System.Diagnostics;

static class Bench
{
    const ulong N = 800;
    const ulong NN = N * N;
    const ulong INF = 0x0FFFFFFFFFFFFFFF;

    static ulong gSeed = 12345;

    static ulong Rnd()
    {
        gSeed = (gSeed * 16807) % 2147483647;
        return gSeed;
    }

    static ulong[] gHeapD;
    static ulong[] gHeapN;
    static ulong gHeapSize = 0;

    static ulong gPopD = 0;
    static ulong gPopN = 0;

    static void Push(ulong d, ulong node)
    {
        ulong i = gHeapSize;
        gHeapSize += 1;
        gHeapD[(int) i] = d;
        gHeapN[(int) i] = node;

        while (i > 0)
        {
            ulong p = (i - 1) >> 1;
            if (gHeapD[(int) p] <= gHeapD[(int) i])
                break;
            ulong td = gHeapD[(int) p];
            gHeapD[(int) p] = gHeapD[(int) i];
            gHeapD[(int) i] = td;
            ulong tn = gHeapN[(int) p];
            gHeapN[(int) p] = gHeapN[(int) i];
            gHeapN[(int) i] = tn;
            i = p;
        }
    }

    static void Pop()
    {
        gPopD = gHeapD[0];
        gPopN = gHeapN[0];
        gHeapSize -= 1;
        gHeapD[0] = gHeapD[(int) gHeapSize];
        gHeapN[0] = gHeapN[(int) gHeapSize];

        ulong i = 0;
        while (true)
        {
            ulong l = 2 * i + 1;
            if (l >= gHeapSize)
                break;
            ulong r = l + 1;
            ulong m = l;
            if (r < gHeapSize && gHeapD[(int) r] < gHeapD[(int) l])
                m = r;
            if (gHeapD[(int) i] <= gHeapD[(int) m])
                break;
            ulong td = gHeapD[(int) m];
            gHeapD[(int) m] = gHeapD[(int) i];
            gHeapD[(int) i] = td;
            ulong tn = gHeapN[(int) m];
            gHeapN[(int) m] = gHeapN[(int) i];
            gHeapN[(int) i] = tn;
            i = m;
        }
    }

    static int Main()
    {
        // ---- data generation (not timed) ----
        var weight = new ulong[NN];
        for (int i = 0; i < (int) NN; i++)
            weight[i] = 1 + (Rnd() % 9);

        // ---- timed work ----
        long start_t = Stopwatch.GetTimestamp();

        var dist = new ulong[NN];
        for (int i = 0; i < (int) NN; i++)
            dist[i] = INF;

        gHeapD = new ulong[NN * 4];
        gHeapN = new ulong[NN * 4];
        gHeapSize = 0;

        dist[0] = 0;
        Push(0, 0);

        ulong pops = 0;
        const ulong Target = NN - 1;

        while (gHeapSize > 0)
        {
            Pop();
            ulong d = gPopD;
            ulong u = gPopN;
            pops += 1;
            if (d > dist[(int) u])
                continue;
            if (u == Target)
                break;

            ulong x = u % N;
            ulong y = u / N;

            if (x > 0)
            {
                ulong v = u - 1;
                ulong nd = d + weight[(int) v];
                if (nd < dist[(int) v])
                {
                    dist[(int) v] = nd;
                    Push(nd, v);
                }
            }
            if (x < N - 1)
            {
                ulong v = u + 1;
                ulong nd = d + weight[(int) v];
                if (nd < dist[(int) v])
                {
                    dist[(int) v] = nd;
                    Push(nd, v);
                }
            }
            if (y > 0)
            {
                ulong v = u - N;
                ulong nd = d + weight[(int) v];
                if (nd < dist[(int) v])
                {
                    dist[(int) v] = nd;
                    Push(nd, v);
                }
            }
            if (y < N - 1)
            {
                ulong v = u + N;
                ulong nd = d + weight[(int) v];
                if (nd < dist[(int) v])
                {
                    dist[(int) v] = nd;
                    Push(nd, v);
                }
            }
        }

        ulong check = dist[(int) Target] * 1000 + (pops % 1000);

        double ms = (Stopwatch.GetTimestamp() - start_t) * 1000.0 / Stopwatch.Frequency;
        Console.WriteLine($"CHECK={check} MS={ms:F6}");
        return 0;
    }
}
