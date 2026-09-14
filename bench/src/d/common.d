module common;

public import core.stdc.stdlib : free, malloc, exit;
public import core.stdc.string : memcmp, memcpy, memset, strlen;
public import core.stdc.math : sqrt;
import core.stdc.stdio : printf;
import core.sys.windows.windows : LARGE_INTEGER, QueryPerformanceCounter, QueryPerformanceFrequency;

alias u64 = ulong;
alias s64 = long;
alias s32 = int;
alias u32 = uint;
alias u8 = ubyte;

__gshared u64 seed = 12345;

u64 rnd()
{
    seed = (seed * 16807) % 2147483647;
    return seed;
}

double now()
{
    LARGE_INTEGER counter, frequency;
    QueryPerformanceCounter(&counter);
    QueryPerformanceFrequency(&frequency);
    return cast(double) counter.QuadPart / cast(double) frequency.QuadPart;
}

void report(u64 check, double t0, double t1)
{
    printf("CHECK=%llu MS=%.6f\n", check, (t1 - t0) * 1000.0);
}

void* xalloc(size_t n)
{
    auto p = malloc(n);
    if (!p)
        exit(1);
    return p;
}
