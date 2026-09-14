module chacha;

import common;
immutable u64 NWORDS = 4194304;
immutable u64 M32  = 0xFFFFFFFF;

u32 add32(u32 left, u32 right)
{
    return cast(u32) (((cast(u64) left) + right) & M32);
}

u32 rol(u32 x, int k)
{
    return cast(u32) (((x << k) | (x >> (32 - k))) & M32);
}

void quarterRound(u32* state, int a, int b, int c, int d)
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

int main()
{

    u32* data = cast(u32*) xalloc(NWORDS * 4);
    for (u64 i = 0; i < NWORDS; i++)
        data[i] = cast(u32) (rnd() & M32);

    u32[8] key = void;
    for (u64 i = 0; i < 8; i++)
        key[i] = cast(u32) (rnd() & M32);

    u32[3] nonce = void;
    for (u64 i = 0; i < 3; i++)
        nonce[i] = cast(u32) (rnd() & M32);

    // Timed work starts after data generation.
    double t0 = now();

    u32[16] initial = void;
    initial[0] = 0x61707865;
    initial[1] = 0x3320646E;
    initial[2] = 0x79622D32;
    initial[3] = 0x6B206574;
    for (int i = 0; i < 8; i++)
        initial[4 + i] = key[i];
    for (int i = 0; i < 3; i++)
        initial[13 + i] = nonce[i];

    u64 offset  = 0;
    u32 counter = 1;
    while (offset < NWORDS)
    {
        initial[12] = counter;

        u32[16] state = void;
        for (int i = 0; i < 16; i++)
            state[i] = initial[i];

        for (int r = 0; r < 10; r++)
        {
            quarterRound(state.ptr, 0, 4, 8, 12);
            quarterRound(state.ptr, 1, 5, 9, 13);
            quarterRound(state.ptr, 2, 6, 10, 14);
            quarterRound(state.ptr, 3, 7, 11, 15);
            quarterRound(state.ptr, 0, 5, 10, 15);
            quarterRound(state.ptr, 1, 6, 11, 12);
            quarterRound(state.ptr, 2, 7, 8, 13);
            quarterRound(state.ptr, 3, 4, 9, 14);
        }

        for (u64 i = 0; i < 16; i++)
            data[offset + i] ^= add32(state[i], initial[i]);

        offset += 16;
        counter += 1;
    }

    u64 check = 0;
    for (u64 i = 0; i < NWORDS; i++)
        check ^= ((cast(u64) data[i]) + i) & M32;

    double t1 = now();
    report(check, t0, t1);

    free(data);
    return 0;
}
