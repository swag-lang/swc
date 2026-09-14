module dijkstra;

import common;
immutable u64 N   = 800;
immutable u64 NN  = N * N;
immutable u64 INF = 0x0FFFFFFFFFFFFFFFUL;

__gshared u64* g_HeapD;
__gshared u64* g_HeapN;
__gshared u64  g_HeapSize = 0;

__gshared u64 g_PopD = 0;
__gshared u64 g_PopN = 0;

void push(u64 d, u64 node)
{
    u64 i = g_HeapSize;
    g_HeapSize += 1;
    g_HeapD[i] = d;
    g_HeapN[i] = node;

    while (i > 0)
    {
        u64 p = (i - 1) >> 1;
        if (g_HeapD[p] <= g_HeapD[i])
            break;
        u64 td     = g_HeapD[p];
        g_HeapD[p] = g_HeapD[i];
        g_HeapD[i] = td;
        u64 tn     = g_HeapN[p];
        g_HeapN[p] = g_HeapN[i];
        g_HeapN[i] = tn;
        i = p;
    }
}

void pop()
{
    g_PopD = g_HeapD[0];
    g_PopN = g_HeapN[0];
    g_HeapSize -= 1;
    g_HeapD[0] = g_HeapD[g_HeapSize];
    g_HeapN[0] = g_HeapN[g_HeapSize];

    u64 i = 0;
    while (true)
    {
        u64 l = 2 * i + 1;
        if (l >= g_HeapSize)
            break;
        u64 r = l + 1;
        u64 m = l;
        if (r < g_HeapSize && g_HeapD[r] < g_HeapD[l])
            m = r;
        if (g_HeapD[i] <= g_HeapD[m])
            break;
        u64 td     = g_HeapD[m];
        g_HeapD[m] = g_HeapD[i];
        g_HeapD[i] = td;
        u64 tn     = g_HeapN[m];
        g_HeapN[m] = g_HeapN[i];
        g_HeapN[i] = tn;
        i = m;
    }
}

int main()
{

    u64* weight = cast(u64*) xalloc(NN * u64.sizeof);
    for (u64 i = 0; i < NN; i++)
        weight[i] = 1 + (rnd() % 9);

    // Timed work starts after data generation.
    double t0 = now();

    u64* dist = cast(u64*) xalloc(NN * u64.sizeof);
    for (u64 i = 0; i < NN; i++)
        dist[i] = INF;

    g_HeapD    = cast(u64*) xalloc(NN * 4 * u64.sizeof);
    g_HeapN    = cast(u64*) xalloc(NN * 4 * u64.sizeof);
    g_HeapSize = 0;

    dist[0] = 0;
    push(0, 0);

    u64       pops   = 0;
    const u64 Target = NN - 1;

    while (g_HeapSize > 0)
    {
        pop();
        u64 d = g_PopD;
        u64 u = g_PopN;
        pops += 1;
        if (d > dist[u])
            continue;
        if (u == Target)
            break;

        u64 x = u % N;
        u64 y = u / N;

        if (x > 0)
        {
            u64 v  = u - 1;
            u64 nd = d + weight[v];
            if (nd < dist[v])
            {
                dist[v] = nd;
                push(nd, v);
            }
        }
        if (x < N - 1)
        {
            u64 v  = u + 1;
            u64 nd = d + weight[v];
            if (nd < dist[v])
            {
                dist[v] = nd;
                push(nd, v);
            }
        }
        if (y > 0)
        {
            u64 v  = u - N;
            u64 nd = d + weight[v];
            if (nd < dist[v])
            {
                dist[v] = nd;
                push(nd, v);
            }
        }
        if (y < N - 1)
        {
            u64 v  = u + N;
            u64 nd = d + weight[v];
            if (nd < dist[v])
            {
                dist[v] = nd;
                push(nd, v);
            }
        }
    }

    u64 check = dist[Target] * 1000 + (pops % 1000);

    double t1 = now();
    report(check, t0, t1);

    free(g_HeapN);
    free(g_HeapD);
    free(dist);
    free(weight);
    return 0;
}
