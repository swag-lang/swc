class Bench
{
    static final long ROWS = 400000;

    static final String[] REGIONS = { "EMEA", "APAC", "AMER", "LATAM", "NORDIC", "IBERIA", "BENELUX", "DACH" };

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
                if (keyLen[(int) idx] == len && memCmp(base, (int) keyOff[(int) idx], (int) off, (int) len) == 0)
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

    static int memCmp(byte[] b, int a, int c, int n)
    {
        for (int i = 0; i < n; i++)
        {
            if (b[(int) (a + i)] != b[(int) (c + i)])
                return b[(int) (a + i)] < b[(int) (c + i)] ? -1 : 1;
        }
        return 0;
    }

    static long writeUInt(byte[] buf, long pos, long v)
    {
        var tmp = new byte[24];
        long n = 0;
        long x = v;
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

        long p = pos;
        long i = n;
        while (i > 0)
        {
            i -= 1;
            buf[(int) p] = tmp[(int) i];
            p += 1;
        }
        return p;
    }

    static long writeUInt2(byte[] buf, long pos, long v)
    {
        buf[(int) pos] = (byte) (48 + (v / 10));
        buf[(int) pos + 1] = (byte) (48 + (v % 10));
        return pos + 2;
    }

    public static void main(String[] args)
    {
        // ---- data generation (not timed) ----
        var text = new byte[(int) (ROWS * 48)];
        long n = 0;

        for (long j = 0; j < ROWS; j++)
        {
            if (j > 0)
            {
                text[(int) n] = (byte) '\n';
                n += 1;
            }

            String region = REGIONS[(int) (rnd() % 8)];
            long y = 2024 + (rnd() % 3);
            long m = 1 + (rnd() % 12);
            long d = 1 + (rnd() % 28);
            long qty = 1 + (rnd() % 50);
            long cents = 100 + (rnd() % 99900);

            n = writeUInt(text, n, j);
            text[(int) n] = (byte) ',';
            n += 1;
            for (int i = 0; i < region.length(); i++)
            {
                text[(int) n] = (byte) region.charAt(i);
                n += 1;
            }
            text[(int) n] = (byte) ',';
            n += 1;
            n = writeUInt(text, n, y);
            text[(int) n] = (byte) '-';
            n += 1;
            n = writeUInt2(text, n, m);
            text[(int) n] = (byte) '-';
            n += 1;
            n = writeUInt2(text, n, d);
            text[(int) n] = (byte) ',';
            n += 1;
            n = writeUInt(text, n, qty);
            text[(int) n] = (byte) ',';
            n += 1;
            n = writeUInt(text, n, cents / 100);
            text[(int) n] = (byte) '.';
            n += 1;
            n = writeUInt2(text, n, cents % 100);
        }

        // ---- timed work ----
        long startTime = System.nanoTime();

        var agg = new ByteMap(64, text);

        var slotCount = new long[64];
        var slotQty = new long[64];
        var slotRev = new double[64];
        var slotMax = new double[64];

        long pos = 0;
        long rows = 0;

        while (pos < n)
        {
            long eol = pos;
            while (eol < n && text[(int) eol] != (byte) '\n')
                eol += 1;

            // field 0: id
            long p = pos;
            while (p < eol && text[(int) p] != (byte) ',')
                p += 1;
            p += 1;

            // field 1: region
            long rs = p;
            while (p < eol && text[(int) p] != (byte) ',')
                p += 1;
            long rlen = p - rs;
            p += 1;

            // field 2: date (skipped)
            while (p < eol && text[(int) p] != (byte) ',')
                p += 1;
            p += 1;

            // field 3: qty
            long qty = 0;
            while (p < eol && text[(int) p] != (byte) ',')
            {
                qty = qty * 10 + (long) (text[(int) p] - 48);
                p += 1;
            }
            p += 1;

            // field 4: price
            long ip = 0;
            while (p < eol && text[(int) p] != (byte) '.')
            {
                ip = ip * 10 + (long) (text[(int) p] - 48);
                p += 1;
            }
            p += 1;
            long fr = 0;
            while (p < eol)
            {
                fr = fr * 10 + (long) (text[(int) p] - 48);
                p += 1;
            }
            double price = (double) ip + (double) fr / 100.0;

            long idx = agg.probe(rs, rlen);
            if (agg.used[(int) idx] == 0)
            {
                int slot = (int) agg.count;
                agg.claim(idx, rs, rlen, (long) slot);
                slotCount[slot] = 1;
                slotQty[slot] = qty;
                slotRev[slot] = (double) qty * price;
                slotMax[slot] = price;
            }
            else
            {
                int slot = (int) agg.val[(int) idx];
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
        var order = new long[64];
        var keyIdx = new long[64];
        long nk = 0;
        for (int i = 0; i < 64; i++)
        {
            if (agg.used[(int) (i)] != 0)
            {
                keyIdx[(int) nk] = (long) i;
                nk += 1;
            }
        }

        for (int i = 0; i < (int) nk; i++)
            order[(int) (i)] = (long) i;
        for (int i = 0; i < (int) nk; i++)
        {
            int best = i;
            for (int j = 0; j < (int) nk; j++)
            {
                if (j <= i)
                    continue;
                int a = (int) keyIdx[(int) order[best]];
                int b = (int) keyIdx[(int) order[(int) (j)]];
                long la = agg.keyLen[a];
                if (agg.keyLen[b] < la)
                    la = agg.keyLen[b];
                int c = memCmp(text, (int) agg.keyOff[b], (int) agg.keyOff[a], (int) la);
                if (c < 0 || (c == 0 && agg.keyLen[b] < agg.keyLen[a]))
                    best = j;
            }
            long t = order[(int) (i)];
            order[(int) (i)] = order[best];
            order[best] = t;
        }

        long check = rows;
        for (int k = 0; k < (int) nk; k++)
        {
            int slot = (int) agg.val[(int) keyIdx[(int) order[k]]];
            check += ((long) k + 1) * ((long) (slotRev[slot] * 100.0 + 0.5) % 1000003);
            check += slotCount[slot] + slotQty[slot] + (long) (slotMax[slot] * 100.0 + 0.5);
        }

        double ms = (System.nanoTime() - startTime) * 1000.0 / 1_000_000_000.0;
        System.out.printf(java.util.Locale.ROOT, "CHECK=%d MS=%.6f%n", check, ms);
        return;
    }
}
