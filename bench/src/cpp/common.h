// Shared prelude for the C++ benchmarks: same RNG, same clock, same report format
// as the Swag originals so checksums can be compared byte for byte.
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

typedef uint64_t u64;
typedef int64_t  s64;
typedef int32_t  s32;
typedef uint8_t  u8;

static u64 g_Seed = 12345;

static inline u64 rnd()
{
    g_Seed = (g_Seed * 16807) % 2147483647ull;
    return g_Seed;
}

static inline double now()
{
    LARGE_INTEGER c, f;
    QueryPerformanceCounter(&c);
    QueryPerformanceFrequency(&f);
    return (double) c.QuadPart / (double) f.QuadPart;
}

static inline void report(u64 check, double t0, double t1)
{
    printf("CHECK=%llu MS=%.6f\n", (unsigned long long) check, (t1 - t0) * 1000.0);
}

static inline void* xalloc(size_t n)
{
    void* p = malloc(n);
    if (!p)
    {
        fprintf(stderr, "oom\n");
        exit(1);
    }
    return p;
}
