using System;
using System.Diagnostics;

static class Bench
{
    const ulong ROWS = 400000;

    static readonly string[] REGIONS = { "EMEA", "APAC", "AMER", "LATAM", "NORDIC", "IBERIA", "BENELUX", "DACH" };

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
                if (KeyLen[(int) idx] == len && MemCmp(Base, (int) KeyOff[(int) idx], (int) off, (int) len) == 0)
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

    static int MemCmp(byte[] b, int a, int c, int n)
    {
        for (int i = 0; i < n; i++)
        {
            if (b[a + i] != b[c + i])
                return b[a + i] < b[c + i] ? -1 : 1;
        }
        return 0;
    }

    static ulong WriteUInt(byte[] buf, ulong pos, ulong v)
    {
        var tmp = new byte[24];
        ulong n = 0;
        ulong x = v;
        if (x == 0)
        {
            tmp[0] = (byte) '0';
            n = 1;
        }
        while (x > 0)
        {
            tmp[(int) n] = (byte) (48 + (x % 10));
            n += 1;
            x /= 10;
        }

        ulong p = pos;
        ulong i = n;
        while (i > 0)
        {
            i -= 1;
            buf[(int) p] = tmp[(int) i];
            p += 1;
        }
        return p;
    }

    static ulong WriteUInt2(byte[] buf, ulong pos, ulong v)
    {
        buf[(int) pos] = (byte) (48 + (v / 10));
        buf[(int) pos + 1] = (byte) (48 + (v % 10));
        return pos + 2;
    }

    static int Main()
    {
        // ---- data generation (not timed) ----
        var text = new byte[ROWS * 48];
        ulong n = 0;

        for (ulong j = 0; j < ROWS; j++)
        {
            if (j > 0)
            {
                text[(int) n] = (byte) '\n';
                n += 1;
            }

            string region = REGIONS[(int) (Rnd() % 8)];
            ulong y = 2024 + (Rnd() % 3);
            ulong m = 1 + (Rnd() % 12);
            ulong d = 1 + (Rnd() % 28);
            ulong qty = 1 + (Rnd() % 50);
            ulong cents = 100 + (Rnd() % 99900);

            n = WriteUInt(text, n, j);
            text[(int) n] = (byte) ',';
            n += 1;
            for (int i = 0; i < region.Length; i++)
            {
                text[(int) n] = (byte) region[i];
                n += 1;
            }
            text[(int) n] = (byte) ',';
            n += 1;
            n = WriteUInt(text, n, y);
            text[(int) n] = (byte) '-';
            n += 1;
            n = WriteUInt2(text, n, m);
            text[(int) n] = (byte) '-';
            n += 1;
            n = WriteUInt2(text, n, d);
            text[(int) n] = (byte) ',';
            n += 1;
            n = WriteUInt(text, n, qty);
            text[(int) n] = (byte) ',';
            n += 1;
            n = WriteUInt(text, n, cents / 100);
            text[(int) n] = (byte) '.';
            n += 1;
            n = WriteUInt2(text, n, cents % 100);
        }

        // ---- timed work ----
        long start_t = Stopwatch.GetTimestamp();

        var agg = new ByteMap(64, text);

        var slotCount = new ulong[64];
        var slotQty = new ulong[64];
        var slotRev = new double[64];
        var slotMax = new double[64];

        ulong pos = 0;
        ulong rows = 0;

        while (pos < n)
        {
            ulong eol = pos;
            while (eol < n && text[(int) eol] != (byte) '\n')
                eol += 1;

            // field 0: id
            ulong p = pos;
            while (p < eol && text[(int) p] != (byte) ',')
                p += 1;
            p += 1;

            // field 1: region
            ulong rs = p;
            while (p < eol && text[(int) p] != (byte) ',')
                p += 1;
            ulong rlen = p - rs;
            p += 1;

            // field 2: date (skipped)
            while (p < eol && text[(int) p] != (byte) ',')
                p += 1;
            p += 1;

            // field 3: qty
            ulong qty = 0;
            while (p < eol && text[(int) p] != (byte) ',')
            {
                qty = qty * 10 + (ulong) (text[(int) p] - 48);
                p += 1;
            }
            p += 1;

            // field 4: price
            ulong ip = 0;
            while (p < eol && text[(int) p] != (byte) '.')
            {
                ip = ip * 10 + (ulong) (text[(int) p] - 48);
                p += 1;
            }
            p += 1;
            ulong fr = 0;
            while (p < eol)
            {
                fr = fr * 10 + (ulong) (text[(int) p] - 48);
                p += 1;
            }
            double price = (double) ip + (double) fr / 100.0;

            ulong idx = agg.Probe(rs, rlen);
            if (agg.Used[(int) idx] == 0)
            {
                int slot = (int) agg.Count;
                agg.Claim(idx, rs, rlen, (ulong) slot);
                slotCount[slot] = 1;
                slotQty[slot] = qty;
                slotRev[slot] = (double) qty * price;
                slotMax[slot] = price;
            }
            else
            {
                int slot = (int) agg.Val[(int) idx];
                slotCount[slot] += 1;
                slotQty[slot] += qty;
                slotRev[slot] += (double) qty * price;
                if (price > slotMax[slot])
                    slotMax[slot] = price;
            }

            rows += 1;
            pos = eol + 1;
        }

        // sort the region keys, then fold them in order
        var order = new ulong[64];
        var keyIdx = new ulong[64];
        ulong nk = 0;
        for (int i = 0; i < 64; i++)
        {
            if (agg.Used[i] != 0)
            {
                keyIdx[(int) nk] = (ulong) i;
                nk += 1;
            }
        }

        for (int i = 0; i < (int) nk; i++)
            order[i] = (ulong) i;
        for (int i = 0; i < (int) nk; i++)
        {
            int best = i;
            for (int j = 0; j < (int) nk; j++)
            {
                if (j <= i)
                    continue;
                int a = (int) keyIdx[(int) order[best]];
                int b = (int) keyIdx[(int) order[j]];
                ulong la = agg.KeyLen[a];
                if (agg.KeyLen[b] < la)
                    la = agg.KeyLen[b];
                int c = MemCmp(text, (int) agg.KeyOff[b], (int) agg.KeyOff[a], (int) la);
                if (c < 0 || (c == 0 && agg.KeyLen[b] < agg.KeyLen[a]))
                    best = j;
            }
            ulong t = order[i];
            order[i] = order[best];
            order[best] = t;
        }

        ulong check = rows;
        for (int k = 0; k < (int) nk; k++)
        {
            int slot = (int) agg.Val[(int) keyIdx[(int) order[k]]];
            check += ((ulong) k + 1) * ((ulong) (slotRev[slot] * 100.0 + 0.5) % 1000003);
            check += slotCount[slot] + slotQty[slot] + (ulong) (slotMax[slot] * 100.0 + 0.5);
        }

        double ms = (Stopwatch.GetTimestamp() - start_t) * 1000.0 / Stopwatch.Frequency;
        Console.WriteLine($"CHECK={check} MS={ms:F6}");
        return 0;
    }
}
