#define _POSIX_C_SOURCE 200809L

#include <openssl/crypto.h>
#include <sodium.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static void require(int valid, const char *message)
{
    if (!valid) {
        fprintf(stderr, "%s\n", message);
        exit(EXIT_FAILURE);
    }
}

static uint64_t ticks(clockid_t clock)
{
    struct timespec now;
    require(clock_gettime(clock, &now) == 0, "could not read clock");
    return (uint64_t)now.tv_sec * UINT64_C(1000000000) + now.tv_nsec;
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "--version")) {
        printf("%s | libsodium %s\n", OpenSSL_version(OPENSSL_VERSION), sodium_version_string());
        return EXIT_SUCCESS;
    }

    require(argc == 6, "expected algorithm, fixture, output, iterations, and offset");
    int (*compare)(const void *, const void *, size_t);
    const char *mode;
    if (!strncmp(argv[1], "openssl-", 8)) {
        compare = CRYPTO_memcmp;
        mode = argv[1] + 8;
    } else {
        require(!strncmp(argv[1], "sodium-", 7), "unexpected library");
        require(sodium_init() >= 0, "could not initialize libsodium");
        compare = sodium_memcmp;
        mode = argv[1] + 7;
    }

    const uint64_t iterations = strtoull(argv[4], NULL, 10);
    const size_t offset = strtoull(argv[5], NULL, 10);
    FILE *input = fopen(argv[2], "rb");
    require(input && fseek(input, 0, SEEK_END) == 0, "could not open input");
    const long file_size = ftell(input);
    require(file_size >= 0 && offset <= (size_t)file_size && iterations, "invalid input size");
    rewind(input);

    const size_t count = (size_t)file_size;
    unsigned char *left_bytes = malloc(count ? count : 1);
    unsigned char *right_bytes = malloc(count ? count : 1);
    require(left_bytes && right_bytes, "could not allocate input buffers");
    require(fread(left_bytes, 1, count, input) == count && fclose(input) == 0, "could not read input");
    memcpy(right_bytes, left_bytes, count);
    const size_t size = count - offset;
    const unsigned char *left = left_bytes + offset;
    unsigned char *right = right_bytes + offset;
    const int equal = !strcmp(mode, "equal");
    if (!equal) {
        const int first = !strcmp(mode, "first");
        require(size && (first || !strcmp(mode, "last")), "invalid mismatch fixture");
        right[first ? 0 : size - 1] ^= 1;
    }

    require((compare(left, right, size) == 0) == equal, "reference warm-up comparison failed");
    uint64_t matches = 0;
    const uint64_t wall_start = ticks(CLOCK_MONOTONIC);
    const uint64_t cpu_start = ticks(CLOCK_PROCESS_CPUTIME_ID);
    for (uint64_t i = 0; i < iterations; ++i)
        matches += compare(left, right, size) == 0;
    const uint64_t cpu_elapsed = ticks(CLOCK_PROCESS_CPUTIME_ID) - cpu_start;
    const uint64_t wall_elapsed = ticks(CLOCK_MONOTONIC) - wall_start;
    require(matches == (equal ? iterations : 0), "reference comparison failed");

    FILE *output = fopen(argv[3], "wb");
    require(output && fputc(matches == iterations, output) != EOF && fclose(output) == 0,
            "could not write result");
    printf("%llu %llu 1000000000\n", (unsigned long long)wall_elapsed, (unsigned long long)cpu_elapsed);
    free(right_bytes);
    free(left_bytes);
    return EXIT_SUCCESS;
}
