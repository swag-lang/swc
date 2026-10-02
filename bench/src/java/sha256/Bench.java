class Bench
{
    static final long MSGSIZE = 8388608;
    static final long M32 = 0xFFFFFFFFL;

    static long gSeed = 12345;

    static long rnd()
    {
        gSeed = (gSeed * 16807) % 2147483647;
        return gSeed;
    }

    static final long[] KTAB = {
        0x428a2f98L, 0x71374491L, 0xb5c0fbcfL, 0xe9b5dba5L, 0x3956c25bL, 0x59f111f1L, 0x923f82a4L, 0xab1c5ed5L,
        0xd807aa98L, 0x12835b01L, 0x243185beL, 0x550c7dc3L, 0x72be5d74L, 0x80deb1feL, 0x9bdc06a7L, 0xc19bf174L,
        0xe49b69c1L, 0xefbe4786L, 0x0fc19dc6L, 0x240ca1ccL, 0x2de92c6fL, 0x4a7484aaL, 0x5cb0a9dcL, 0x76f988daL,
        0x983e5152L, 0xa831c66dL, 0xb00327c8L, 0xbf597fc7L, 0xc6e00bf3L, 0xd5a79147L, 0x06ca6351L, 0x14292967L,
        0x27b70a85L, 0x2e1b2138L, 0x4d2c6dfcL, 0x53380d13L, 0x650a7354L, 0x766a0abbL, 0x81c2c92eL, 0x92722c85L,
        0xa2bfe8a1L, 0xa81a664bL, 0xc24b8b70L, 0xc76c51a3L, 0xd192e819L, 0xd6990624L, 0xf40e3585L, 0x106aa070L,
        0x19a4c116L, 0x1e376c08L, 0x2748774cL, 0x34b0bcb5L, 0x391c0cb3L, 0x4ed8aa4aL, 0x5b9cca4fL, 0x682e6ff3L,
        0x748f82eeL, 0x78a5636fL, 0x84c87814L, 0x8cc70208L, 0x90befffaL, 0xa4506cebL, 0xbef9a3f7L, 0xc67178f2L};

    static long rotr(long x, int k)
    {
        return ((x >> k) | (x << (32 - k))) & M32;
    }

    public static void main(String[] args)
    {
        // ---- data generation (not timed) ----
        var msg = new byte[(int) (MSGSIZE)];
        for (long i = 0; i < MSGSIZE; i++)
            msg[(int) i] = (byte) (rnd() % 256);

        // ---- timed work ----
        long startTime = System.nanoTime();

        long totalBits = MSGSIZE * 8;
        long nb = MSGSIZE;
        var buf = new byte[(int) (MSGSIZE + 128)];
        System.arraycopy(msg, 0, buf, 0, (int) MSGSIZE);
        buf[(int) nb] = (byte) 0x80;
        nb += 1;
        while ((nb % 64) != 56)
        {
            buf[(int) nb] = 0;
            nb += 1;
        }
        for (int s = 0; s < 8; s++)
        {
            buf[(int) nb] = (byte) ((totalBits >> (56 - 8 * s)) & 0xFFL);
            nb += 1;
        }

        long h0 = 0x6a09e667L;
        long h1 = 0xbb67ae85L;
        long h2 = 0x3c6ef372L;
        long h3 = 0xa54ff53aL;
        long h4 = 0x510e527fL;
        long h5 = 0x9b05688cL;
        long h6 = 0x1f83d9abL;
        long h7 = 0x5be0cd19L;

        var w = new long[64];
        long nblocks = nb / 64;

        for (long b = 0; b < nblocks; b++)
        {
            long o = b * 64;
            for (int t = 0; t < 16; t++)
            {
                int p = (int) (o + (long) t * 4);
                w[t] = ((buf[p] & 255L) << 24) | ((buf[(int) (p + 1)] & 255L) << 16) | ((buf[(int) (p + 2)] & 255L) << 8) | (buf[(int) (p + 3)] & 255L);
            }

            for (int t = 16; t < 64; t++)
            {
                long x = w[(int) (t - 15)];
                long y = w[(int) (t - 2)];
                long s0 = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3);
                long s1 = rotr(y, 17) ^ rotr(y, 19) ^ (y >> 10);
                w[t] = (w[(int) (t - 16)] + s0 + w[(int) (t - 7)] + s1) & M32;
            }

            long a = h0;
            long bb = h1;
            long c = h2;
            long d = h3;
            long e = h4;
            long f = h5;
            long g = h6;
            long h = h7;

            for (int i = 0; i < 64; i++)
            {
                long s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
                long ch = (e & f) ^ ((~e & M32) & g);
                long t1 = (h + s1 + ch + KTAB[(int) (i)] + w[(int) (i)]) & M32;
                long s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
                long maj = (a & bb) ^ (a & c) ^ (bb & c);
                long t2 = (s0 + maj) & M32;
                h = g;
                g = f;
                f = e;
                e = (d + t1) & M32;
                d = c;
                c = bb;
                bb = a;
                a = (t1 + t2) & M32;
            }

            h0 = (h0 + a) & M32;
            h1 = (h1 + bb) & M32;
            h2 = (h2 + c) & M32;
            h3 = (h3 + d) & M32;
            h4 = (h4 + e) & M32;
            h5 = (h5 + f) & M32;
            h6 = (h6 + g) & M32;
            h7 = (h7 + h) & M32;
        }

        long check = h0 ^ h1 ^ h2 ^ h3 ^ h4 ^ h5 ^ h6 ^ h7;

        double ms = (System.nanoTime() - startTime) * 1000.0 / 1_000_000_000.0;
        System.out.printf(java.util.Locale.ROOT, "CHECK=%d MS=%.6f%n", check, ms);
        return;
    }
}
