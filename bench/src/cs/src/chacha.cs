using System;
using System.Diagnostics;

static class Bench
{
    const ulong NWORDS = 262144; // 32-bit words, one mebibyte of key stream
    const ulong M32 = 0xFFFFFFFF;

    static ulong gSeed = 12345;

    static ulong Rnd()
    {
        gSeed = (gSeed * 16807) % 2147483647;
        return gSeed;
    }

    static uint Add32(uint left, uint right)
    {
        return (uint) ((((ulong) left) + right) & M32);
    }

    static uint Rol(uint x, int k)
    {
        return (x << k) | (x >> (32 - k));
    }

    static void QuarterRound(uint[] state, int a, int b, int c, int d)
    {
        state[a] = Add32(state[a], state[b]);
        state[d] ^= state[a];
        state[d] = Rol(state[d], 16);
        state[c] = Add32(state[c], state[d]);
        state[b] ^= state[c];
        state[b] = Rol(state[b], 12);
        state[a] = Add32(state[a], state[b]);
        state[d] ^= state[a];
        state[d] = Rol(state[d], 8);
        state[c] = Add32(state[c], state[d]);
        state[b] ^= state[c];
        state[b] = Rol(state[b], 7);
    }

    static int Main()
    {
        // ---- data generation (not timed) ----
        var data = new uint[NWORDS];
        for (ulong i = 0; i < NWORDS; i++)
            data[(int) i] = (uint) (Rnd() & M32);

        var key = new uint[8];
        for (int i = 0; i < 8; i++)
            key[i] = (uint) (Rnd() & M32);

        var nonce = new uint[3];
        for (int i = 0; i < 3; i++)
            nonce[i] = (uint) (Rnd() & M32);

        // ---- timed work ----
        long start_t = Stopwatch.GetTimestamp();

        var initial = new uint[16];
        initial[0] = 0x61707865;
        initial[1] = 0x3320646E;
        initial[2] = 0x79622D32;
        initial[3] = 0x6B206574;
        for (int i = 0; i < 8; i++)
            initial[4 + i] = key[i];
        for (int i = 0; i < 3; i++)
            initial[13 + i] = nonce[i];

        var state = new uint[16];
        ulong offset = 0;
        uint counter = 1;
        while (offset < NWORDS)
        {
            initial[12] = counter;

            for (int i = 0; i < 16; i++)
                state[i] = initial[i];

            for (int r = 0; r < 10; r++)
            {
                QuarterRound(state, 0, 4, 8, 12);
                QuarterRound(state, 1, 5, 9, 13);
                QuarterRound(state, 2, 6, 10, 14);
                QuarterRound(state, 3, 7, 11, 15);
                QuarterRound(state, 0, 5, 10, 15);
                QuarterRound(state, 1, 6, 11, 12);
                QuarterRound(state, 2, 7, 8, 13);
                QuarterRound(state, 3, 4, 9, 14);
            }

            for (ulong i = 0; i < 16; i++)
                data[(int) (offset + i)] ^= Add32(state[(int) i], initial[(int) i]);

            offset += 16;
            counter += 1;
        }

        ulong check = 0;
        for (ulong i = 0; i < NWORDS; i++)
            check ^= (((ulong) data[(int) i]) + i) & M32;

        double ms = (Stopwatch.GetTimestamp() - start_t) * 1000.0 / Stopwatch.Frequency;
        Console.WriteLine($"CHECK={check} MS={ms:F6}");
        return 0;
    }
}
