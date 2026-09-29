module lz77;

import common;
immutable u64 DATA_SIZE = 1 << 20;
immutable u64 WORDS     = 512;
immutable u64 HASH_SIZE = 65536;
immutable s64 WINDOW    = 32768;
immutable s64 MIN_MATCH = 4;
immutable s64 MAX_MATCH = 258;
immutable s64 MAX_CHAIN = 32;

u64 hashAt(const(u8)* d, s64 p)
{
    return (((d[p] * 33UL + d[p + 1]) * 33 + d[p + 2]) * 33 + d[p + 3]) % HASH_SIZE;
}

int main()
{
    // ---- data generation (not timed) ----
    u8*  letters   = cast(u8*) xalloc(WORDS * 10);
    u64* wordStart = cast(u64*) xalloc(WORDS * u64.sizeof);
    u64* wordLen   = cast(u64*) xalloc(WORDS * u64.sizeof);
    u64  used      = 0;
    for (u64 k = 0; k < WORDS; k++)
    {
        u64 len      = 2 + rnd() % 8;
        wordStart[k] = used;
        wordLen[k]   = len;
        for (u64 j = 0; j < len; j++)
            letters[used + j] = cast(u8) (97 + rnd() % 26);
        used += len;
    }

    immutable s64 n = cast(s64) DATA_SIZE;
    u8* data = cast(u8*) xalloc(DATA_SIZE);
    s64 pos  = 0;
    while (pos < n)
    {
        u64 w = rnd() % WORDS;
        for (u64 j = 0; j < wordLen[w] && pos < n; j++)
            data[pos++] = letters[wordStart[w] + j];
        if (pos < n)
            data[pos++] = ' ';
    }

    // ---- timed work ----
    double t0 = now();

    s64* head = cast(s64*) xalloc(HASH_SIZE * s64.sizeof);
    s64* prev = cast(s64*) xalloc(WINDOW * s64.sizeof);
    for (u64 i = 0; i < HASH_SIZE; i++)
        head[i] = -1;
    for (s64 i = 0; i < WINDOW; i++)
        prev[i] = -1;

    u8* comp  = cast(u8*) xalloc(DATA_SIZE * 2 + 16);
    s64 csize = 0;

    s64 i = 0;
    while (i + MIN_MATCH <= n)
    {
        s64 best  = 0;
        s64 dist  = 0;
        s64 limit = n - i < MAX_MATCH ? n - i : MAX_MATCH;
        u64 h     = hashAt(data, i);
        s64 cand  = head[h];
        s64 chain = 0;
        while (cand >= 0 && i - cand < WINDOW && chain < MAX_CHAIN)
        {
            s64 l = 0;
            while (l < limit && data[cand + l] == data[i + l])
                l++;
            if (l > best)
            {
                best = l;
                dist = i - cand;
                if (l == limit)
                    break;
            }
            cand = prev[cand % WINDOW];
            chain++;
        }

        prev[i % WINDOW] = head[h];
        head[h]          = i;

        if (best >= MIN_MATCH)
        {
            comp[csize++] = 1;
            comp[csize++] = cast(u8) (best - MIN_MATCH);
            comp[csize++] = cast(u8) ((dist - 1) % 256);
            comp[csize++] = cast(u8) ((dist - 1) / 256);
            for (s64 p = i + 1; p < i + best; p++)
            {
                if (p + MIN_MATCH <= n)
                {
                    u64 hp           = hashAt(data, p);
                    prev[p % WINDOW] = head[hp];
                    head[hp]         = p;
                }
            }
            i += best;
        }
        else
        {
            comp[csize++] = 0;
            comp[csize++] = data[i];
            i++;
        }
    }

    while (i < n)
    {
        comp[csize++] = 0;
        comp[csize++] = data[i];
        i++;
    }

    // ---- decompress and verify ----
    u8* output = cast(u8*) xalloc(DATA_SIZE);
    s64 o = 0;
    s64 c = 0;
    while (c < csize)
    {
        if (comp[c] == 0)
        {
            output[o++] = comp[c + 1];
            c += 2;
        }
        else
        {
            s64 len  = comp[c + 1] + MIN_MATCH;
            s64 back = comp[c + 2] + comp[c + 3] * 256 + 1;
            for (s64 k = 0; k < len; k++)
            {
                output[o] = output[o - back];
                o++;
            }
            c += 4;
        }
    }

    bool same = o == n;
    for (s64 k = 0; same && k < n; k++)
    {
        if (output[k] != data[k])
            same = false;
    }

    u64 hc = 0;
    for (s64 k = 0; k < csize; k++)
        hc = (hc * 31 + comp[k]) % 1000003;

    u64 check = same ? cast(u64) csize * 1000003 + hc : 0;

    double t1 = now();
    report(check, t0, t1);

    free(output);
    free(comp);
    free(prev);
    free(head);
    free(data);
    free(wordLen);
    free(wordStart);
    free(letters);
    return 0;
}
