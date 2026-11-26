#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

enum { StateBytes = 1344 };
extern void ecma_old_placement(unsigned char *, const unsigned char *, size_t);
extern void ecma_new_placement(unsigned char *, const unsigned char *, size_t);

static uint64_t cpu_time(void)
{
    struct timespec sample;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &sample) != 0)
        abort();
    return (uint64_t)sample.tv_sec * UINT64_C(1000000000) + sample.tv_nsec;
}

int main(void)
{
    static const size_t sizes[] = {4096, 65536, 1048576};
    static const size_t offsets[] = {0, 1, 31};
    void (*const kernels[])(unsigned char *, const unsigned char *, size_t) = {
        ecma_old_placement, ecma_new_placement
    };
    unsigned char *input = aligned_alloc(64, 1048576 + 64);
    _Alignas(64) unsigned char states[2][StateBytes];
    _Alignas(64) unsigned char seed[StateBytes];
    _Alignas(64) unsigned char working[StateBytes];
    if (!input) return 1;
    for (size_t i = 0; i < 1048576 + 64; ++i)
        input[i] = (unsigned char)((i ^ (i >> 8) ^ (i >> 14)) * 47 + 13);
    for (size_t i = 0; i < StateBytes; ++i)
        seed[i] = (unsigned char)((i ^ (i >> 3)) * 29 + 7);

    for (size_t size = 0; size < 3; ++size)
        for (size_t offset = 0; offset < 3; ++offset)
        {
            const size_t length = sizes[size];
            const unsigned char *bytes = input + offsets[offset];
            for (size_t kernel = 0; kernel < 2; ++kernel)
            {
                memcpy(states[kernel], seed, StateBytes);
                kernels[kernel](states[kernel], bytes, length);
            }
            if (memcmp(states[0], states[1], StateBytes)) return 2;
            const size_t iterations = (256U * 1024 * 1024) / length;
            for (size_t round = 0; round < 13; ++round)
            {
                double rates[2];
                for (size_t item = 0; item < 2; ++item)
                {
                    const size_t kernel = (round + item) & 1;
                    memcpy(working, seed, StateBytes);
                    const uint64_t before = cpu_time();
                    for (size_t i = 0; i < iterations; ++i)
                        kernels[kernel](working, bytes, length);
                    rates[kernel] = (double)(iterations * length) / (cpu_time() - before);
                    memcpy(states[kernel], working, StateBytes);
                }
                if (memcmp(states[0], states[1], StateBytes)) return 3;
                printf("%zu %zu %zu %.6f %.6f\n", length, offsets[offset], round, rates[0], rates[1]);
            }
        }
    free(input);
    return 0;
}
