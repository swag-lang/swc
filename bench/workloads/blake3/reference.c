#define _POSIX_C_SOURCE 200809L
#include <blake3.h>
#include <blake3_impl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if defined(BLAKE3_USE_TBB)
void set_tbb_threads(unsigned int count);
const char *tbb_version(void);
#endif

static void require(int condition, const char *message)
{
    if (!condition)
    {
        fprintf(stderr, "%s\n", message);
        exit(2);
    }
}

static uint64_t nanoseconds(clockid_t clock)
{
    struct timespec stamp;
    require(clock_gettime(clock, &stamp) == 0, "clock_gettime failed");
    return (uint64_t)stamp.tv_sec * UINT64_C(1000000000) + (uint64_t)stamp.tv_nsec;
}

static void hash(const uint8_t *input, size_t length, uint8_t output[BLAKE3_OUT_LEN], size_t split, unsigned int workers)
{
#if !defined(BLAKE3_USE_TBB)
    (void)workers;
#endif
    blake3_hasher state;
    blake3_hasher_init(&state);
#if defined(BLAKE3_USE_TBB)
    if (workers)
        blake3_hasher_update_tbb(&state, input, length);
    else
#endif
    if (!split)
        blake3_hasher_update(&state, input, length);
    else
        for (size_t offset = 0; offset < length; offset += split)
        {
            const size_t remaining = length - offset;
            blake3_hasher_update(&state, input + offset, remaining < split ? remaining : split);
        }
    blake3_hasher_finalize(&state, output, BLAKE3_OUT_LEN);
}

int main(int argc, char **argv)
{
    if (argc == 2 && strcmp(argv[1], "--version") == 0)
    {
        printf("BLAKE3 C %s | dispatch width %zu", blake3_version(), blake3_simd_degree());
#if defined(BLAKE3_USE_TBB)
        printf(" | oneTBB %s", tbb_version());
#endif
        putchar('\n');
        return 0;
    }

    require(argc == 6, "Expected operation, input, output, iterations and offset");
    size_t split = 0;
    unsigned int workers = 0;
    if (strcmp(argv[1], "blake3-stream-4096") == 0)
        split = 4096;
    else if (strcmp(argv[1], "blake3-stream-65536") == 0)
        split = 65536;
    else if (strcmp(argv[1], "blake3-stream-1048576") == 0)
        split = 1048576;
#if defined(BLAKE3_USE_TBB)
    else if (strcmp(argv[1], "blake3-tbb2") == 0)
        workers = 2;
    else if (strcmp(argv[1], "blake3-tbb4") == 0)
        workers = 4;
#endif
    else
        require(strcmp(argv[1], "blake3") == 0, "Unknown BLAKE3 operation");

#if defined(BLAKE3_USE_TBB)
    if (workers)
        set_tbb_threads(workers);
#endif

    char *end;
    const uint64_t iterations = strtoull(argv[4], &end, 10);
    require(*end == '\0' && iterations != 0, "Expected positive iteration count");
    const size_t offset = strtoull(argv[5], &end, 10);
    require(*end == '\0', "Expected numeric offset");
    FILE *source = fopen(argv[2], "rb");
    require(source && fseek(source, 0, SEEK_END) == 0, "Cannot open input");
    const long length = ftell(source);
    require(length >= 0 && offset <= (size_t)length && fseek(source, 0, SEEK_SET) == 0, "Input offset or length out of range");
    uint8_t *buffer = malloc((size_t)length + 1);
    require(buffer && fread(buffer, 1, (size_t)length, source) == (size_t)length, "Cannot read input");
    fclose(source);

    uint8_t output[BLAKE3_OUT_LEN];
    hash(buffer + offset, (size_t)length - offset, output, split, workers);
    const uint64_t wall_start = nanoseconds(CLOCK_MONOTONIC);
    const uint64_t cpu_start = nanoseconds(CLOCK_PROCESS_CPUTIME_ID);
    for (uint64_t i = 0; i < iterations; i++)
        hash(buffer + offset, (size_t)length - offset, output, split, workers);
    const uint64_t cpu_elapsed = nanoseconds(CLOCK_PROCESS_CPUTIME_ID) - cpu_start;
    const uint64_t wall_elapsed = nanoseconds(CLOCK_MONOTONIC) - wall_start;

    FILE *dest = fopen(argv[3], "wb");
    require(dest && fwrite(output, 1, sizeof(output), dest) == sizeof(output) && fclose(dest) == 0, "Cannot write digest");
    printf("%llu %llu 1000000000\n", (unsigned long long)wall_elapsed, (unsigned long long)cpu_elapsed);
    free(buffer);
    return 0;
}
