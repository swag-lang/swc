class Bench
{
    static final int DATA_SIZE = 1 << 20;
    static final int WORDS = 512;
    static final int HASH_SIZE = 65536;
    static final int WINDOW = 32768;
    static final int MIN_MATCH = 4;
    static final int MAX_MATCH = 258;
    static final int MAX_CHAIN = 32;

    static long gSeed = 12345;

    static long rnd()
    {
        gSeed = (gSeed * 16807) % 2147483647;
        return gSeed;
    }

    static int hashAt(byte[] d, int p)
    {
        return (((d[p] * 33 + d[(int) (p + 1)]) * 33 + d[(int) (p + 2)]) * 33 + d[(int) (p + 3)]) % HASH_SIZE;
    }

    public static void main(String[] args)
    {
        // ---- data generation (not timed) ----
        var letters = new byte[(int) (WORDS * 10)];
        var wordStart = new int[WORDS];
        var wordLen = new int[WORDS];
        int used = 0;
        for (int k = 0; k < WORDS; k++)
        {
            int len = 2 + (int) (rnd() % 8);
            wordStart[k] = used;
            wordLen[k] = len;
            for (int j = 0; j < len; j++)
                letters[(int) (used + j)] = (byte) (97 + rnd() % 26);
            used += len;
        }

        final int n = DATA_SIZE;
        var data = new byte[n];
        int pos = 0;
        while (pos < n)
        {
            int w = (int) (rnd() % WORDS);
            for (int j = 0; j < wordLen[w] && pos < n; j++)
                data[(int) (pos++)] = letters[(int) (wordStart[w] + j)];
            if (pos < n)
                data[(int) (pos++)] = (byte) ' ';
        }

        // ---- timed work ----
        long startTime = System.nanoTime();

        var head = new int[HASH_SIZE];
        var prev = new int[WINDOW];
        for (int k = 0; k < HASH_SIZE; k++)
            head[k] = -1;
        for (int k = 0; k < WINDOW; k++)
            prev[k] = -1;

        var comp = new byte[(int) (n * 2 + 16)];
        int csize = 0;

        int i = 0;
        while (i + MIN_MATCH <= n)
        {
            int best = 0;
            int dist = 0;
            int limit = n - i < MAX_MATCH ? n - i : MAX_MATCH;
            int h = hashAt(data, i);
            int cand = head[h];
            int chain = 0;
            while (cand >= 0 && i - cand < WINDOW && chain < MAX_CHAIN)
            {
                int l = 0;
                while (l < limit && data[(int) (cand + l)] == data[(int) (i + l)])
                    l++;
                if (l > best)
                {
                    best = l;
                    dist = i - cand;
                    if (l == limit)
                        break;
                }
                cand = prev[(int) (cand % WINDOW)];
                chain++;
            }

            prev[(int) (i % WINDOW)] = head[h];
            head[h] = i;

            if (best >= MIN_MATCH)
            {
                comp[(int) (csize++)] = 1;
                comp[(int) (csize++)] = (byte) (best - MIN_MATCH);
                comp[(int) (csize++)] = (byte) ((dist - 1) % 256);
                comp[(int) (csize++)] = (byte) ((dist - 1) / 256);
                for (int p = i + 1; p < i + best; p++)
                {
                    if (p + MIN_MATCH <= n)
                    {
                        int hp = hashAt(data, p);
                        prev[(int) (p % WINDOW)] = head[hp];
                        head[hp] = p;
                    }
                }
                i += best;
            }
            else
            {
                comp[(int) (csize++)] = 0;
                comp[(int) (csize++)] = data[i];
                i++;
            }
        }

        while (i < n)
        {
            comp[(int) (csize++)] = 0;
            comp[(int) (csize++)] = data[i];
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
                output[(int) (o++)] = comp[(int) (c + 1)];
                c += 2;
            }
            else
            {
                int len = (comp[(int) (c + 1)] & 255) + MIN_MATCH;
                int back = (comp[(int) (c + 2)] & 255) + (comp[(int) (c + 3)] & 255) * 256 + 1;
                for (int k = 0; k < len; k++)
                {
                    output[o] = output[(int) (o - back)];
                    o++;
                }
                c += 4;
            }
        }

        boolean same = o == n;
        for (int k = 0; same && k < n; k++)
        {
            if (output[k] != data[k])
                same = false;
        }

        long hc = 0;
        for (int k = 0; k < csize; k++)
            hc = (hc * 31 + (comp[k] & 255)) % 1000003;

        long check = same ? (long) csize * 1000003 + hc : 0;

        double ms = (System.nanoTime() - startTime) * 1000.0 / 1_000_000_000.0;
        System.out.printf(java.util.Locale.ROOT, "CHECK=%d MS=%.6f%n", check, ms);
        return;
    }
}
