class Bench
{
    static final long NWORDS = 4194304; // 32-bit words, sixteen mebibytes of key stream
    static final long M32 = 0xFFFFFFFFL;

    static long gSeed = 12345;

    static long rnd()
    {
        gSeed = (gSeed * 16807) % 2147483647;
        return gSeed;
    }

    static int add32(int left, int right)
    {
        return (int) ((((long) left) + right) & M32);
    }

    static int rol(int x, int k)
    {
        return (x << k) | (x >>> (32 - k));
    }

    static void quarterRound(int[] state, int a, int b, int c, int d)
    {
        state[a] = add32(state[a], state[b]);
        state[d] ^= state[a];
        state[d] = rol(state[d], 16);
        state[c] = add32(state[c], state[d]);
        state[b] ^= state[c];
        state[b] = rol(state[b], 12);
        state[a] = add32(state[a], state[b]);
        state[d] ^= state[a];
        state[d] = rol(state[d], 8);
        state[c] = add32(state[c], state[d]);
        state[b] ^= state[c];
        state[b] = rol(state[b], 7);
    }

    public static void main(String[] args)
    {
        // ---- data generation (not timed) ----
        var data = new int[(int) (NWORDS)];
        for (long i = 0; i < NWORDS; i++)
            data[(int) i] = (int) (rnd() & M32);

        var key = new int[8];
        for (int i = 0; i < 8; i++)
            key[(int) (i)] = (int) (rnd() & M32);

        var nonce = new int[3];
        for (int i = 0; i < 3; i++)
            nonce[(int) (i)] = (int) (rnd() & M32);

        // ---- timed work ----
        long startTime = System.nanoTime();

        var initial = new int[16];
        initial[0] = 0x61707865;
        initial[1] = 0x3320646E;
        initial[2] = 0x79622D32;
        initial[3] = 0x6B206574;
        for (int i = 0; i < 8; i++)
            initial[(int) (4 + i)] = key[(int) (i)];
        for (int i = 0; i < 3; i++)
            initial[(int) (13 + i)] = nonce[(int) (i)];

        var state = new int[16];
        long offset = 0;
        int counter = 1;
        while (offset < NWORDS)
        {
            initial[12] = counter;

            for (int i = 0; i < 16; i++)
                state[(int) (i)] = initial[(int) (i)];

            for (int r = 0; r < 10; r++)
            {
                quarterRound(state, 0, 4, 8, 12);
                quarterRound(state, 1, 5, 9, 13);
                quarterRound(state, 2, 6, 10, 14);
                quarterRound(state, 3, 7, 11, 15);
                quarterRound(state, 0, 5, 10, 15);
                quarterRound(state, 1, 6, 11, 12);
                quarterRound(state, 2, 7, 8, 13);
                quarterRound(state, 3, 4, 9, 14);
            }

            for (long i = 0; i < 16; i++)
                data[(int) (offset + i)] ^= add32(state[(int) i], initial[(int) i]);

            offset += 16;
            counter += 1;
        }

        long check = 0;
        for (long i = 0; i < NWORDS; i++)
            check ^= (((long) data[(int) i]) + i) & M32;

        double ms = (System.nanoTime() - startTime) * 1000.0 / 1_000_000_000.0;
        System.out.printf(java.util.Locale.ROOT, "CHECK=%d MS=%.6f%n", check, ms);
        return;
    }
}
