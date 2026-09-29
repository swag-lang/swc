using System;
using System.Diagnostics;

static class Bench
{
    const int DATA_SIZE = 1 << 20;
    const int WORDS = 512;
    const int HASH_SIZE = 65536;
    const int WINDOW = 32768;
    const int MIN_MATCH = 4;
    const int MAX_MATCH = 258;
    const int MAX_CHAIN = 32;

    static ulong gSeed = 12345;

    static ulong Rnd()
    {
        gSeed = (gSeed * 16807) % 2147483647;
        return gSeed;
    }

    static int HashAt(byte[] d, int p)
    {
        return (((d[p] * 33 + d[p + 1]) * 33 + d[p + 2]) * 33 + d[p + 3]) % HASH_SIZE;
    }

    static int Main()
    {
        // ---- data generation (not timed) ----
        var letters = new byte[WORDS * 10];
        var wordStart = new int[WORDS];
        var wordLen = new int[WORDS];
        int used = 0;
        for (int k = 0; k < WORDS; k++)
        {
            int len = 2 + (int) (Rnd() % 8);
            wordStart[k] = used;
            wordLen[k] = len;
            for (int j = 0; j < len; j++)
                letters[used + j] = (byte) (97 + Rnd() % 26);
            used += len;
        }

        const int n = DATA_SIZE;
        var data = new byte[n];
        int pos = 0;
        while (pos < n)
        {
            int w = (int) (Rnd() % WORDS);
            for (int j = 0; j < wordLen[w] && pos < n; j++)
                data[pos++] = letters[wordStart[w] + j];
            if (pos < n)
                data[pos++] = (byte) ' ';
        }

        // ---- timed work ----
        long start_t = Stopwatch.GetTimestamp();

        var head = new int[HASH_SIZE];
        var prev = new int[WINDOW];
        for (int k = 0; k < HASH_SIZE; k++)
            head[k] = -1;
        for (int k = 0; k < WINDOW; k++)
            prev[k] = -1;

        var comp = new byte[n * 2 + 16];
        int csize = 0;

        int i = 0;
        while (i + MIN_MATCH <= n)
        {
            int best = 0;
            int dist = 0;
            int limit = n - i < MAX_MATCH ? n - i : MAX_MATCH;
            int h = HashAt(data, i);
            int cand = head[h];
            int chain = 0;
            while (cand >= 0 && i - cand < WINDOW && chain < MAX_CHAIN)
            {
                int l = 0;
                while (l < limit && data[cand + l] == data[i + l])
                    l++;
                if (l > best)
                {
                    best = l;
                    dist = i - cand;
                    if (l == limit)
                        break;
                }
                cand = prev[cand % WINDOW];
                chain++;
            }

            prev[i % WINDOW] = head[h];
            head[h] = i;

            if (best >= MIN_MATCH)
            {
                comp[csize++] = 1;
                comp[csize++] = (byte) (best - MIN_MATCH);
                comp[csize++] = (byte) ((dist - 1) % 256);
                comp[csize++] = (byte) ((dist - 1) / 256);
                for (int p = i + 1; p < i + best; p++)
                {
                    if (p + MIN_MATCH <= n)
                    {
                        int hp = HashAt(data, p);
                        prev[p % WINDOW] = head[hp];
                        head[hp] = p;
                    }
                }
                i += best;
            }
            else
            {
                comp[csize++] = 0;
                comp[csize++] = data[i];
                i++;
            }
        }

        while (i < n)
        {
            comp[csize++] = 0;
            comp[csize++] = data[i];
            i++;
        }

        // ---- decompress and verify ----
        var output = new byte[n];
        int o = 0;
        int c = 0;
        while (c < csize)
        {
            if (comp[c] == 0)
            {
                output[o++] = comp[c + 1];
                c += 2;
            }
            else
            {
                int len = comp[c + 1] + MIN_MATCH;
                int back = comp[c + 2] + comp[c + 3] * 256 + 1;
                for (int k = 0; k < len; k++)
                {
                    output[o] = output[o - back];
                    o++;
                }
                c += 4;
            }
        }

        bool same = o == n;
        for (int k = 0; same && k < n; k++)
        {
            if (output[k] != data[k])
                same = false;
        }

        ulong hc = 0;
        for (int k = 0; k < csize; k++)
            hc = (hc * 31 + comp[k]) % 1000003;

        ulong check = same ? (ulong) csize * 1000003 + hc : 0;

        double ms = (Stopwatch.GetTimestamp() - start_t) * 1000.0 / Stopwatch.Frequency;
        Console.WriteLine($"CHECK={check} MS={ms:F6}");
        return 0;
    }
}
