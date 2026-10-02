class Bench
{
    static final long VOCAB = 5000;
    static final long WORDS = 2000000;
    static final long CAP = 16384;

    static long gSeed = 12345;

    static long rnd()
    {
        gSeed = (gSeed * 16807) % 2147483647;
        return gSeed;
    }

    static final class ByteMap
    {
        public long[] keyOff;
        public long[] keyLen;
        public long[] val;
        public byte[] used;
        public byte[] base;
        public long mask;
        public long count;

        public ByteMap(long capacity, byte[] b)
        {
            int c = (int) capacity;
            keyOff = new long[c];
            keyLen = new long[c];
            val = new long[c];
            used = new byte[c];
            base = b;
            mask = capacity - 1;
            count = 0;
        }

        public long probe(long off, long len)
        {
            long h = 2166136261L;
            for (long i = 0; i < len; i++)
            {
                h ^= base[(int) (off + i)];
                h = (h * 16777619) & 0xFFFFFFFFL;
            }

            long idx = h & mask;
            while (used[(int) idx] != 0)
            {
                if (keyLen[(int) idx] == len && memEq(base, (int) keyOff[(int) idx], (int) off, (int) len))
                    return idx;
                idx = (idx + 1) & mask;
            }

            return idx;
        }

        public void claim(long idx, long off, long len, long value)
        {
            int i = (int) idx;
            used[(int) (i)] = 1;
            keyOff[(int) (i)] = off;
            keyLen[(int) (i)] = len;
            val[(int) (i)] = value;
            count += 1;
        }
    }

    static boolean memEq(byte[] b, int a, int c, int n)
    {
        for (int i = 0; i < n; i++)
            if (b[(int) (a + i)] != b[(int) (c + i)])
                return false;
        return true;
    }

    static int memCmp(byte[] b, int a, int c, int n)
    {
        for (int i = 0; i < n; i++)
        {
            if (b[(int) (a + i)] != b[(int) (c + i)])
                return b[(int) (a + i)] < b[(int) (c + i)] ? -1 : 1;
        }
        return 0;
    }

    static byte[] gText;
    static long[] gCnt;
    static long[] gOff;
    static long[] gLen;
    static long[] gIdx;

    // count descending, then key bytes ascending
    static boolean less(long a, long b)
    {
        int ia = (int) a, ib = (int) b;
        if (gCnt[ia] != gCnt[(int) (ib)])
            return gCnt[ia] > gCnt[(int) (ib)];

        long n = gLen[ia];
        if (gLen[(int) (ib)] < n)
            n = gLen[(int) (ib)];
        int c = memCmp(gText, (int) gOff[ia], (int) gOff[(int) (ib)], (int) n);
        if (c != 0)
            return c < 0;
        return gLen[ia] < gLen[(int) (ib)];
    }

    static void qSort(long lowIn, long highIn)
    {
        long low = lowIn;
        long high = highIn;

        while (low < high)
        {
            long p = gIdx[(int) ((low + high) / 2)];
            long i = low;
            long j = high;

            while (i <= j)
            {
                while (less(gIdx[(int) (i)], p))
                    i += 1;
                while (less(p, gIdx[(int) (j)]))
                    j -= 1;
                if (i <= j)
                {
                    long t = gIdx[(int) (i)];
                    gIdx[(int) (i)] = gIdx[(int) (j)];
                    gIdx[(int) (j)] = t;
                    i += 1;
                    j -= 1;
                }
            }

            qSort(low, j);
            low = i;
        }
    }

    public static void main(String[] args)
    {
        // ---- data generation (not timed) ----
        var vocabBytes = new byte[(int) (VOCAB * 16)];
        var vocabOff = new long[(int) (VOCAB)];
        var vocabLen = new long[(int) (VOCAB)];

        long vp = 0;
        for (long i = 0; i < VOCAB; i++)
        {
            long nn = i + 1;
            long l = 3 + (i % 6);
            vocabOff[(int) i] = vp;
            vocabLen[(int) i] = l;
            for (long k = 0; k < l; k++)
            {
                vocabBytes[(int) vp] = (byte) (97 + (nn % 26));
                vp += 1;
                nn = nn / 26 + 7 * k;
            }
        }

        gText = new byte[(int) (WORDS * 12)];
        long n = 0;
        for (long j = 0; j < WORDS; j++)
        {
            long idx = rnd() % VOCAB;
            long o = vocabOff[(int) idx];
            long l = vocabLen[(int) idx];
            for (long k = 0; k < l; k++)
            {
                gText[(int) n] = vocabBytes[(int) (o + k)];
                n += 1;
            }
            gText[(int) n] = (j + 1) % 12 == 0 ? (byte) '\n' : (byte) ' ';
            n += 1;
        }

        // ---- timed work ----
        long startTime = System.nanoTime();

        var counts = new ByteMap(CAP, gText);

        long start = 0;
        boolean open = false;
        long ii = 0;

        while (ii < n)
        {
            byte c = gText[(int) ii];
            if (c >= 97 && c <= 122)
            {
                if (!open)
                {
                    start = ii;
                    open = true;
                }
            }
            else if (open)
            {
                long idx = counts.probe(start, ii - start);
                if (counts.used[(int) idx] == 0)
                    counts.claim(idx, start, ii - start, 1);
                else
                    counts.val[(int) idx] += 1;
                open = false;
            }
            ii += 1;
        }

        if (open)
        {
            long idx = counts.probe(start, n - start);
            if (counts.used[(int) idx] == 0)
                counts.claim(idx, start, n - start, 1);
            else
                counts.val[(int) idx] += 1;
        }

        long distinct = counts.count;
        gCnt = new long[(int) (distinct)];
        gOff = new long[(int) (distinct)];
        gLen = new long[(int) (distinct)];
        gIdx = new long[(int) (distinct)];

        long ni = 0;
        for (int s = 0; s < (int) CAP; s++)
        {
            if (counts.used[s] == 0)
                continue;
            gCnt[(int) ni] = counts.val[s];
            gOff[(int) ni] = counts.keyOff[s];
            gLen[(int) ni] = counts.keyLen[s];
            gIdx[(int) ni] = ni;
            ni += 1;
        }

        qSort(0, (long) distinct - 1);

        long check = distinct * 7;
        for (long k = 0; k < 20; k++)
            check += (k + 1) * gCnt[(int) gIdx[(int) k]];

        double ms = (System.nanoTime() - startTime) * 1000.0 / 1_000_000_000.0;
        System.out.printf(java.util.Locale.ROOT, "CHECK=%d MS=%.6f%n", check, ms);
        return;
    }
}
