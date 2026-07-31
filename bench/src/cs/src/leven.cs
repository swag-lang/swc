using System;
using System.Diagnostics;

static class Bench
{
    const ulong DICT = 6000;
    const ulong QUERIES = 40;
    const ulong MAXLEN = 3;

    static ulong gSeed = 12345;

    static ulong Rnd()
    {
        gSeed = (gSeed * 16807) % 2147483647;
        return gSeed;
    }

    static int Main()
    {
        // ---- data generation (not timed) ----
        var bytes = new byte[DICT * 16];
        var wordOff = new ulong[DICT];
        var wordLen = new ulong[DICT];

        ulong wp = 0;
        for (ulong i = 0; i < DICT; i++)
        {
            ulong n = i + 1;
            ulong l = 4 + (i % 7);
            wordOff[(int) i] = wp;
            wordLen[(int) i] = l;
            for (ulong k = 0; k < l; k++)
            {
                bytes[(int) wp] = (byte) (97 + (n % 26));
                wp += 1;
                n = n / 26 + 7 * k;
            }
        }

        var qBytes = new byte[QUERIES * 32];
        var qOff = new ulong[QUERIES];
        var qLen = new ulong[QUERIES];

        ulong qp = 0;
        for (int q = 0; q < (int) QUERIES; q++)
        {
            var tmp = new byte[32];
            ulong src = Rnd() % DICT;
            ulong nw = wordLen[(int) src];
            for (int i = 0; i < (int) nw; i++)
                tmp[i] = bytes[(int) wordOff[(int) src] + i];

            for (int rep = 0; rep < 2; rep++)
            {
                ulong p = Rnd() % nw;
                ulong op = Rnd() % 3;
                byte c = (byte) (97 + (Rnd() % 26));
                if (op == 0)
                {
                    tmp[(int) p] = c;
                }
                else if (op == 1)
                {
                    if (nw > 2)
                    {
                        ulong i = p;
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
                    ulong i = nw;
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
                qBytes[(int) qp] = tmp[i];
                qp += 1;
            }
        }

        // ---- timed work ----
        long start_t = Stopwatch.GetTimestamp();

        var row0 = new ulong[64];
        var row1 = new ulong[64];

        long check = 0;
        for (int q = 0; q < (int) QUERIES; q++)
        {
            ulong ao = qOff[q];
            ulong la = qLen[q];
            ulong best = 1073741824;
            long bestIdx = -1;

            for (int i = 0; i < (int) DICT; i++)
            {
                ulong bo = wordOff[i];
                ulong lb = wordLen[i];
                ulong d = la > lb ? la - lb : lb - la;
                if (d > MAXLEN)
                    continue;

                for (int j = 0; j < (int) lb + 1; j++)
                    row0[j] = (ulong) j;

                for (ulong x = 0; x < la; x++)
                {
                    row1[0] = x + 1;
                    byte ca = qBytes[(int) (ao + x)];
                    for (int y = 0; y < (int) lb; y++)
                    {
                        ulong cost = ca == bytes[(int) bo + y] ? 0UL : 1UL;
                        ulong v = row0[y] + cost;
                        ulong v2 = row0[y + 1] + 1;
                        if (v2 < v)
                            v = v2;
                        v2 = row1[y] + 1;
                        if (v2 < v)
                            v = v2;
                        row1[y + 1] = v;
                    }
                    for (int j = 0; j < (int) lb + 1; j++)
                        row0[j] = row1[j];
                }

                ulong dd = row0[(int) lb];
                if (dd < best)
                {
                    best = dd;
                    bestIdx = i;
                }
            }

            check += (long) best * 31 + bestIdx;
        }

        double ms = (Stopwatch.GetTimestamp() - start_t) * 1000.0 / Stopwatch.Frequency;
        Console.WriteLine($"CHECK={(ulong) check} MS={ms:F6}");
        return 0;
    }
}
