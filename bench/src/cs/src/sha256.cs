using System;
using System.Diagnostics;

static class Bench
{
    const ulong MSGSIZE = 524288;
    const ulong M32 = 0xFFFFFFFF;

    static ulong gSeed = 12345;

    static ulong Rnd()
    {
        gSeed = (gSeed * 16807) % 2147483647;
        return gSeed;
    }

    static readonly ulong[] KTAB = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

    static ulong Rotr(ulong x, int k)
    {
        return ((x >> k) | (x << (32 - k))) & M32;
    }

    static int Main()
    {
        // ---- data generation (not timed) ----
        var msg = new byte[MSGSIZE];
        for (ulong i = 0; i < MSGSIZE; i++)
            msg[(int) i] = (byte) (Rnd() % 256);

        // ---- timed work ----
        long start_t = Stopwatch.GetTimestamp();

        ulong totalBits = MSGSIZE * 8;
        ulong nb = MSGSIZE;
        var buf = new byte[MSGSIZE + 128];
        Array.Copy(msg, buf, (int) MSGSIZE);
        buf[(int) nb] = 0x80;
        nb += 1;
        while ((nb % 64) != 56)
        {
            buf[(int) nb] = 0;
            nb += 1;
        }
        for (int s = 0; s < 8; s++)
        {
            buf[(int) nb] = (byte) ((totalBits >> (56 - 8 * s)) & 0xFF);
            nb += 1;
        }

        ulong h0 = 0x6a09e667;
        ulong h1 = 0xbb67ae85;
        ulong h2 = 0x3c6ef372;
        ulong h3 = 0xa54ff53a;
        ulong h4 = 0x510e527f;
        ulong h5 = 0x9b05688c;
        ulong h6 = 0x1f83d9ab;
        ulong h7 = 0x5be0cd19;

        var w = new ulong[64];
        ulong nblocks = nb / 64;

        for (ulong b = 0; b < nblocks; b++)
        {
            ulong o = b * 64;
            for (int t = 0; t < 16; t++)
            {
                int p = (int) (o + (ulong) t * 4);
                w[t] = ((ulong) buf[p] << 24) | ((ulong) buf[p + 1] << 16) | ((ulong) buf[p + 2] << 8) | (ulong) buf[p + 3];
            }

            for (int t = 16; t < 64; t++)
            {
                ulong x = w[t - 15];
                ulong y = w[t - 2];
                ulong s0 = Rotr(x, 7) ^ Rotr(x, 18) ^ (x >> 3);
                ulong s1 = Rotr(y, 17) ^ Rotr(y, 19) ^ (y >> 10);
                w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & M32;
            }

            ulong a = h0;
            ulong bb = h1;
            ulong c = h2;
            ulong d = h3;
            ulong e = h4;
            ulong f = h5;
            ulong g = h6;
            ulong h = h7;

            for (int i = 0; i < 64; i++)
            {
                ulong s1 = Rotr(e, 6) ^ Rotr(e, 11) ^ Rotr(e, 25);
                ulong ch = (e & f) ^ ((~e & M32) & g);
                ulong t1 = (h + s1 + ch + KTAB[i] + w[i]) & M32;
                ulong s0 = Rotr(a, 2) ^ Rotr(a, 13) ^ Rotr(a, 22);
                ulong maj = (a & bb) ^ (a & c) ^ (bb & c);
                ulong t2 = (s0 + maj) & M32;
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

        ulong check = h0 ^ h1 ^ h2 ^ h3 ^ h4 ^ h5 ^ h6 ^ h7;

        double ms = (Stopwatch.GetTimestamp() - start_t) * 1000.0 / Stopwatch.Frequency;
        Console.WriteLine($"CHECK={check} MS={ms:F6}");
        return 0;
    }
}
