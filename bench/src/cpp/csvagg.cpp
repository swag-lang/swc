#include "bytemap.h"

static const u64 ROWS = 400000;

static const char* REGIONS[8] = {"EMEA", "APAC", "AMER", "LATAM", "NORDIC", "IBERIA", "BENELUX", "DACH"};

static u64 writeUInt(u8* buf, u64 pos, u64 v)
{
    u8  tmp[24];
    u64 n = 0;
    u64 x = v;
    if (x == 0)
    {
        tmp[0] = '0';
        n      = 1;
    }
    while (x > 0)
    {
        tmp[n] = (u8) (48 + (x % 10));
        n += 1;
        x /= 10;
    }

    u64 p = pos;
    u64 i = n;
    while (i > 0)
    {
        i -= 1;
        buf[p] = tmp[i];
        p += 1;
    }
    return p;
}

static u64 writeUInt2(u8* buf, u64 pos, u64 v)
{
    buf[pos]     = (u8) (48 + (v / 10));
    buf[pos + 1] = (u8) (48 + (v % 10));
    return pos + 2;
}

int main()
{
    // ---- data generation (not timed) ----
    u8* text = (u8*) xalloc(ROWS * 48);
    u64 n    = 0;

    for (u64 j = 0; j < ROWS; j++)
    {
        if (j > 0)
        {
            text[n] = '\n';
            n += 1;
        }

        const char* region = REGIONS[rnd() % 8];
        u64         y      = 2024 + (rnd() % 3);
        u64         m      = 1 + (rnd() % 12);
        u64         d      = 1 + (rnd() % 28);
        u64         qty    = 1 + (rnd() % 50);
        u64         cents  = 100 + (rnd() % 99900);

        n       = writeUInt(text, n, j);
        text[n] = ',';
        n += 1;
        u64 rl = strlen(region);
        for (u64 i = 0; i < rl; i++)
        {
            text[n] = (u8) region[i];
            n += 1;
        }
        text[n] = ',';
        n += 1;
        n       = writeUInt(text, n, y);
        text[n] = '-';
        n += 1;
        n       = writeUInt2(text, n, m);
        text[n] = '-';
        n += 1;
        n       = writeUInt2(text, n, d);
        text[n] = ',';
        n += 1;
        n       = writeUInt(text, n, qty);
        text[n] = ',';
        n += 1;
        n       = writeUInt(text, n, cents / 100);
        text[n] = '.';
        n += 1;
        n = writeUInt2(text, n, cents % 100);
    }

    // ---- timed work ----
    double t0 = now();

    ByteMap agg;
    mapInit(&agg, 64, text);

    u64*    slotCount = (u64*) xalloc(64 * sizeof(u64));
    u64*    slotQty   = (u64*) xalloc(64 * sizeof(u64));
    double* slotRev   = (double*) xalloc(64 * sizeof(double));
    double* slotMax   = (double*) xalloc(64 * sizeof(double));

    u64 pos  = 0;
    u64 rows = 0;

    while (pos < n)
    {
        u64 eol = pos;
        while (eol < n && text[eol] != '\n')
            eol += 1;

        // field 0: id
        u64 p = pos;
        while (p < eol && text[p] != ',')
            p += 1;
        p += 1;

        // field 1: region
        u64 rs = p;
        while (p < eol && text[p] != ',')
            p += 1;
        u64 rlen = p - rs;
        p += 1;

        // field 2: date (skipped)
        while (p < eol && text[p] != ',')
            p += 1;
        p += 1;

        // field 3: qty
        u64 qty = 0;
        while (p < eol && text[p] != ',')
        {
            qty = qty * 10 + (u64) (text[p] - 48);
            p += 1;
        }
        p += 1;

        // field 4: price
        u64 ip = 0;
        while (p < eol && text[p] != '.')
        {
            ip = ip * 10 + (u64) (text[p] - 48);
            p += 1;
        }
        p += 1;
        u64 fr = 0;
        while (p < eol)
        {
            fr = fr * 10 + (u64) (text[p] - 48);
            p += 1;
        }
        double price = (double) ip + (double) fr / 100.0;

        u64 idx = mapProbe(&agg, rs, rlen);
        if (agg.used[idx] == 0)
        {
            u64 slot = agg.count;
            mapClaim(&agg, idx, rs, rlen, slot);
            slotCount[slot] = 1;
            slotQty[slot]   = qty;
            slotRev[slot]   = (double) qty * price;
            slotMax[slot]   = price;
        }
        else
        {
            u64 slot = agg.val[idx];
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
    u64 order[64];
    u64 keyIdx[64];
    u64 nk = 0;
    for (u64 i = 0; i < 64; i++)
    {
        if (agg.used[i] != 0)
        {
            keyIdx[nk] = i;
            nk += 1;
        }
    }

    for (u64 i = 0; i < nk; i++)
        order[i] = i;
    for (u64 i = 0; i < nk; i++)
    {
        u64 best = i;
        for (u64 j = 0; j < nk; j++)
        {
            if (j <= i)
                continue;
            u64 a  = keyIdx[order[best]];
            u64 b  = keyIdx[order[j]];
            u64 la = agg.keyLen[a];
            if (agg.keyLen[b] < la)
                la = agg.keyLen[b];
            int c = memcmp(&text[agg.keyOff[b]], &text[agg.keyOff[a]], (size_t) la);
            if (c < 0 || (c == 0 && agg.keyLen[b] < agg.keyLen[a]))
                best = j;
        }
        u64 t       = order[i];
        order[i]    = order[best];
        order[best] = t;
    }

    u64 check = rows;
    for (u64 k = 0; k < nk; k++)
    {
        u64 slot = agg.val[keyIdx[order[k]]];
        check += (k + 1) * ((u64) (slotRev[slot] * 100.0 + 0.5) % 1000003);
        check += slotCount[slot] + slotQty[slot] + (u64) (slotMax[slot] * 100.0 + 0.5);
    }

    double t1 = now();
    report(check, t0, t1);
    return 0;
}
