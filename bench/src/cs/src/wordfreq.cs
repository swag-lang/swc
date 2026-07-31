using System;
using System.Diagnostics;

static class Bench
{
    const ulong VOCAB = 5000;
    const ulong WORDS = 2000000;
    const ulong CAP = 16384;

    static ulong gSeed = 12345;

    static ulong Rnd()
    {
        gSeed = (gSeed * 16807) % 2147483647;
        return gSeed;
    }

    sealed class ByteMap
    {
        public ulong[] KeyOff;
        public ulong[] KeyLen;
        public ulong[] Val;
        public byte[] Used;
        public byte[] Base;
        public ulong Mask;
        public ulong Count;

        public ByteMap(ulong capacity, byte[] b)
        {
            int c = (int) capacity;
            KeyOff = new ulong[c];
            KeyLen = new ulong[c];
            Val = new ulong[c];
            Used = new byte[c];
            Base = b;
            Mask = capacity - 1;
            Count = 0;
        }

        public ulong Probe(ulong off, ulong len)
        {
            ulong h = 2166136261;
            for (ulong i = 0; i < len; i++)
            {
                h ^= Base[(int) (off + i)];
                h = (h * 16777619) & 0xFFFFFFFF;
            }

            ulong idx = h & Mask;
            while (Used[(int) idx] != 0)
            {
                if (KeyLen[(int) idx] == len && MemEq(Base, (int) KeyOff[(int) idx], (int) off, (int) len))
                    return idx;
                idx = (idx + 1) & Mask;
            }

            return idx;
        }

        public void Claim(ulong idx, ulong off, ulong len, ulong value)
        {
            int i = (int) idx;
            Used[i] = 1;
            KeyOff[i] = off;
            KeyLen[i] = len;
            Val[i] = value;
            Count += 1;
        }
    }

    static bool MemEq(byte[] b, int a, int c, int n)
    {
        for (int i = 0; i < n; i++)
            if (b[a + i] != b[c + i])
                return false;
        return true;
    }

    static int MemCmp(byte[] b, int a, int c, int n)
    {
        for (int i = 0; i < n; i++)
        {
            if (b[a + i] != b[c + i])
                return b[a + i] < b[c + i] ? -1 : 1;
        }
        return 0;
    }

    static byte[] gText;
    static ulong[] gCnt;
    static ulong[] gOff;
    static ulong[] gLen;
    static ulong[] gIdx;

    // count descending, then key bytes ascending
    static bool Less(ulong a, ulong b)
    {
        int ia = (int) a, ib = (int) b;
        if (gCnt[ia] != gCnt[ib])
            return gCnt[ia] > gCnt[ib];

        ulong n = gLen[ia];
        if (gLen[ib] < n)
            n = gLen[ib];
        int c = MemCmp(gText, (int) gOff[ia], (int) gOff[ib], (int) n);
        if (c != 0)
            return c < 0;
        return gLen[ia] < gLen[ib];
    }

    static void QSort(long lowIn, long highIn)
    {
        long low = lowIn;
        long high = highIn;

        while (low < high)
        {
            ulong p = gIdx[(low + high) / 2];
            long i = low;
            long j = high;

            while (i <= j)
            {
                while (Less(gIdx[i], p))
                    i += 1;
                while (Less(p, gIdx[j]))
                    j -= 1;
                if (i <= j)
                {
                    ulong t = gIdx[i];
                    gIdx[i] = gIdx[j];
                    gIdx[j] = t;
                    i += 1;
                    j -= 1;
                }
            }

            QSort(low, j);
            low = i;
        }
    }

    static int Main()
    {
        // ---- data generation (not timed) ----
        var vocabBytes = new byte[VOCAB * 16];
        var vocabOff = new ulong[VOCAB];
        var vocabLen = new ulong[VOCAB];

        ulong vp = 0;
        for (ulong i = 0; i < VOCAB; i++)
        {
            ulong nn = i + 1;
            ulong l = 3 + (i % 6);
            vocabOff[(int) i] = vp;
            vocabLen[(int) i] = l;
            for (ulong k = 0; k < l; k++)
            {
                vocabBytes[(int) vp] = (byte) (97 + (nn % 26));
                vp += 1;
                nn = nn / 26 + 7 * k;
            }
        }

        gText = new byte[WORDS * 12];
        ulong n = 0;
        for (ulong j = 0; j < WORDS; j++)
        {
            ulong idx = Rnd() % VOCAB;
            ulong o = vocabOff[(int) idx];
            ulong l = vocabLen[(int) idx];
            for (ulong k = 0; k < l; k++)
            {
                gText[(int) n] = vocabBytes[(int) (o + k)];
                n += 1;
            }
            gText[(int) n] = (j + 1) % 12 == 0 ? (byte) '\n' : (byte) ' ';
            n += 1;
        }

        // ---- timed work ----
        long start_t = Stopwatch.GetTimestamp();

        var counts = new ByteMap(CAP, gText);

        ulong start = 0;
        bool open = false;
        ulong ii = 0;

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
                ulong idx = counts.Probe(start, ii - start);
                if (counts.Used[(int) idx] == 0)
                    counts.Claim(idx, start, ii - start, 1);
                else
                    counts.Val[(int) idx] += 1;
                open = false;
            }
            ii += 1;
        }

        if (open)
        {
            ulong idx = counts.Probe(start, n - start);
            if (counts.Used[(int) idx] == 0)
                counts.Claim(idx, start, n - start, 1);
            else
                counts.Val[(int) idx] += 1;
        }

        ulong distinct = counts.Count;
        gCnt = new ulong[distinct];
        gOff = new ulong[distinct];
        gLen = new ulong[distinct];
        gIdx = new ulong[distinct];

        ulong ni = 0;
        for (int s = 0; s < (int) CAP; s++)
        {
            if (counts.Used[s] == 0)
                continue;
            gCnt[(int) ni] = counts.Val[s];
            gOff[(int) ni] = counts.KeyOff[s];
            gLen[(int) ni] = counts.KeyLen[s];
            gIdx[(int) ni] = ni;
            ni += 1;
        }

        QSort(0, (long) distinct - 1);

        ulong check = distinct * 7;
        for (ulong k = 0; k < 20; k++)
            check += (k + 1) * gCnt[(int) gIdx[(int) k]];

        double ms = (Stopwatch.GetTimestamp() - start_t) * 1000.0 / Stopwatch.Frequency;
        Console.WriteLine($"CHECK={check} MS={ms:F6}");
        return 0;
    }
}
