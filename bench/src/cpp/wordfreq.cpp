#include "bytemap.h"

static const u64 VOCAB = 5000;
static const u64 WORDS = 2000000;
static const u64 CAP   = 16384;

static u8*  g_Text;
static u64* g_Cnt;
static u64* g_Off;
static u64* g_Len;
static u64* g_Idx;

// count descending, then key bytes ascending
static bool less(u64 a, u64 b)
{
    if (g_Cnt[a] != g_Cnt[b])
        return g_Cnt[a] > g_Cnt[b];

    u64 n = g_Len[a];
    if (g_Len[b] < n)
        n = g_Len[b];
    int c = memcmp(&g_Text[g_Off[a]], &g_Text[g_Off[b]], (size_t) n);
    if (c != 0)
        return c < 0;
    return g_Len[a] < g_Len[b];
}

static void qsortIdx(s64 lowIn, s64 highIn)
{
    s64 low  = lowIn;
    s64 high = highIn;

    while (low < high)
    {
        u64 p = g_Idx[(u64) ((low + high) / 2)];
        s64 i = low;
        s64 j = high;

        while (i <= j)
        {
            while (less(g_Idx[(u64) i], p))
                i += 1;
            while (less(p, g_Idx[(u64) j]))
                j -= 1;
            if (i <= j)
            {
                u64 t         = g_Idx[(u64) i];
                g_Idx[(u64) i] = g_Idx[(u64) j];
                g_Idx[(u64) j] = t;
                i += 1;
                j -= 1;
            }
        }

        qsortIdx(low, j);
        low = i;
    }
}

int main()
{
    // ---- data generation (not timed) ----
    u8*  vocabBytes = (u8*) xalloc(VOCAB * 16);
    u64* vocabOff   = (u64*) xalloc(VOCAB * sizeof(u64));
    u64* vocabLen   = (u64*) xalloc(VOCAB * sizeof(u64));

    u64 vp = 0;
    for (u64 i = 0; i < VOCAB; i++)
    {
        u64 nn = i + 1;
        u64 l  = 3 + (i % 6);
        vocabOff[i] = vp;
        vocabLen[i] = l;
        for (u64 k = 0; k < l; k++)
        {
            vocabBytes[vp] = (u8) (97 + (nn % 26));
            vp += 1;
            nn = nn / 26 + 7 * k;
        }
    }

    g_Text = (u8*) xalloc(WORDS * 12);
    u64 n  = 0;
    for (u64 j = 0; j < WORDS; j++)
    {
        u64 idx = rnd() % VOCAB;
        u64 o   = vocabOff[idx];
        u64 l   = vocabLen[idx];
        for (u64 k = 0; k < l; k++)
        {
            g_Text[n] = vocabBytes[o + k];
            n += 1;
        }
        if ((j + 1) % 12 == 0)
            g_Text[n] = '\n';
        else
            g_Text[n] = ' ';
        n += 1;
    }

    // ---- timed work ----
    double t0 = now();

    ByteMap counts;
    mapInit(&counts, CAP, g_Text);

    u64  start = 0;
    bool open  = false;
    u64  i     = 0;

    while (i < n)
    {
        u8 c = g_Text[i];
        if (c >= 97 && c <= 122)
        {
            if (!open)
            {
                start = i;
                open  = true;
            }
        }
        else if (open)
        {
            u64 idx = mapProbe(&counts, start, i - start);
            if (counts.used[idx] == 0)
                mapClaim(&counts, idx, start, i - start, 1);
            else
                counts.val[idx] += 1;
            open = false;
        }
        i += 1;
    }

    if (open)
    {
        u64 idx = mapProbe(&counts, start, n - start);
        if (counts.used[idx] == 0)
            mapClaim(&counts, idx, start, n - start, 1);
        else
            counts.val[idx] += 1;
    }

    u64 distinct = counts.count;
    g_Cnt        = (u64*) xalloc(distinct * sizeof(u64));
    g_Off        = (u64*) xalloc(distinct * sizeof(u64));
    g_Len        = (u64*) xalloc(distinct * sizeof(u64));
    g_Idx        = (u64*) xalloc(distinct * sizeof(u64));

    u64 ni = 0;
    for (u64 s = 0; s < CAP; s++)
    {
        if (counts.used[s] == 0)
            continue;
        g_Cnt[ni] = counts.val[s];
        g_Off[ni] = counts.keyOff[s];
        g_Len[ni] = counts.keyLen[s];
        g_Idx[ni] = ni;
        ni += 1;
    }

    qsortIdx(0, (s64) distinct - 1);

    u64 check = distinct * 7;
    for (u64 k = 0; k < 20; k++)
        check += (k + 1) * g_Cnt[g_Idx[k]];

    double t1 = now();
    report(check, t0, t1);
    return 0;
}
