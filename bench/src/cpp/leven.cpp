#include "common.h"

static const u64 DICT    = 6000;
static const u64 QUERIES = 40;
static const u64 MAXLEN  = 3;

static u8*  g_Bytes;
static u64* g_WordOff;
static u64* g_WordLen;

static u8*  g_QBytes;
static u64* g_QOff;
static u64* g_QLen;

int main()
{
    // ---- data generation (not timed) ----
    g_Bytes   = (u8*) xalloc(DICT * 16);
    g_WordOff = (u64*) xalloc(DICT * sizeof(u64));
    g_WordLen = (u64*) xalloc(DICT * sizeof(u64));

    u64 wp = 0;
    for (u64 i = 0; i < DICT; i++)
    {
        u64 n = i + 1;
        u64 l = 4 + (i % 7);
        g_WordOff[i] = wp;
        g_WordLen[i] = l;
        for (u64 k = 0; k < l; k++)
        {
            g_Bytes[wp] = (u8) (97 + (n % 26));
            wp += 1;
            n = n / 26 + 7 * k;
        }
    }

    g_QBytes = (u8*) xalloc(QUERIES * 32);
    g_QOff   = (u64*) xalloc(QUERIES * sizeof(u64));
    g_QLen   = (u64*) xalloc(QUERIES * sizeof(u64));

    u64 qp = 0;
    for (u64 q = 0; q < QUERIES; q++)
    {
        u8  tmp[32];
        u64 src = rnd() % DICT;
        u64 nw  = g_WordLen[src];
        for (u64 i = 0; i < nw; i++)
            tmp[i] = g_Bytes[g_WordOff[src] + i];

        for (u64 rep = 0; rep < 2; rep++)
        {
            u64 p  = rnd() % nw;
            u64 op = rnd() % 3;
            u8  c  = (u8) (97 + (rnd() % 26));
            if (op == 0)
            {
                tmp[p] = c;
            }
            else if (op == 1)
            {
                if (nw > 2)
                {
                    u64 i = p;
                    while (i + 1 < nw)
                    {
                        tmp[i] = tmp[i + 1];
                        i += 1;
                    }
                    nw -= 1;
                }
            }
            else
            {
                u64 i = nw;
                while (i > p)
                {
                    tmp[i] = tmp[i - 1];
                    i -= 1;
                }
                tmp[p] = c;
                nw += 1;
            }
        }

        g_QOff[q] = qp;
        g_QLen[q] = nw;
        for (u64 i = 0; i < nw; i++)
        {
            g_QBytes[qp] = tmp[i];
            qp += 1;
        }
    }

    // ---- timed work ----
    double t0 = now();

    u64 row0[64];
    u64 row1[64];

    s64 check = 0;
    for (u64 q = 0; q < QUERIES; q++)
    {
        u64 ao      = g_QOff[q];
        u64 la      = g_QLen[q];
        u64 best    = 1073741824;
        s64 bestIdx = -1;

        for (u64 i = 0; i < DICT; i++)
        {
            u64 bo = g_WordOff[i];
            u64 lb = g_WordLen[i];
            u64 d  = 0;
            if (la > lb)
                d = la - lb;
            else
                d = lb - la;
            if (d > MAXLEN)
                continue;

            for (u64 j = 0; j < lb + 1; j++)
                row0[j] = j;

            for (u64 x = 0; x < la; x++)
            {
                row1[0] = x + 1;
                u8 ca   = g_QBytes[ao + x];
                for (u64 y = 0; y < lb; y++)
                {
                    u64 cost = 1;
                    if (ca == g_Bytes[bo + y])
                        cost = 0;
                    u64 v  = row0[y] + cost;
                    u64 v2 = row0[y + 1] + 1;
                    if (v2 < v)
                        v = v2;
                    v2 = row1[y] + 1;
                    if (v2 < v)
                        v = v2;
                    row1[y + 1] = v;
                }
                for (u64 j = 0; j < lb + 1; j++)
                    row0[j] = row1[j];
            }

            u64 dd = row0[lb];
            if (dd < best)
            {
                best    = dd;
                bestIdx = (s64) i;
            }
        }

        check += (s64) best * 31 + bestIdx;
    }

    double t1 = now();
    report((u64) check, t0, t1);
    return 0;
}
