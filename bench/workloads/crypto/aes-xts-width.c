#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <immintrin.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static inline __m128i next_key(__m128i previous, __m128i substituted)
{
    __m128i pairs = _mm_xor_si128(previous, _mm_slli_si128(previous, 4));
    return _mm_xor_si128(_mm_xor_si128(pairs, _mm_slli_si128(pairs, 8)), substituted);
}

static inline void expand_key(const unsigned char key[32], __m128i expanded[15])
{
    static const uint32_t rcon[7] = {1, 2, 4, 8, 16, 32, 64};
    const __m128i rotate = _mm_setr_epi8(13, 14, 15, 12, 13, 14, 15, 12,
                                       13, 14, 15, 12, 13, 14, 15, 12);
    const __m128i last = _mm_setr_epi8(12, 13, 14, 15, 12, 13, 14, 15,
                                     12, 13, 14, 15, 12, 13, 14, 15);
    const __m128i zero = _mm_setzero_si128();
    __m128i left = _mm_loadu_si128((const __m128i *)key);
    __m128i right = _mm_loadu_si128((const __m128i *)(key + 16));
    expanded[0] = left;
    expanded[1] = right;
    for (unsigned pair = 0; pair < 7; ++pair) {
        __m128i sub = _mm_aesenclast_si128(_mm_shuffle_epi8(right, rotate), _mm_set1_epi32(rcon[pair]));
        left = next_key(left, sub);
        expanded[2 * pair + 2] = left;
        if (pair == 6) break;
        right = next_key(right, _mm_aesenclast_si128(_mm_shuffle_epi8(left, last), zero));
        expanded[2 * pair + 3] = right;
    }
}

#ifndef XTS_MODEL
#define XTS_MODEL 0
#endif

static const unsigned char dual_aes_key[64] = "0123456789abcdefghijklmnopqrstuv"
                                              "vutsrqponmlkjihgfedcba9876543210";
static const unsigned char tweak_bytes[16] = "0123456789abcdef";

static inline __m128i next_tweak(__m128i value)
{
    __m128i signs = _mm_srai_epi32(value, 31);
    __m128i carries = _mm_shuffle_epi32(signs, _MM_SHUFFLE(0, 1, 0, 3));
    return _mm_xor_si128(_mm_slli_epi64(value, 1),
                        _mm_and_si128(carries, _mm_set_epi64x(1, 0x87)));
}

static inline void invert_schedule(const __m128i forward[15], __m128i inverse[15])
{
    inverse[0] = forward[14];
    for (unsigned round = 1; round < 14; ++round)
        inverse[round] = _mm_aesimc_si128(forward[14 - round]);
    inverse[14] = forward[0];
}

static inline __m128i aes_one(__m128i value, const __m128i keys[15], int decrypt)
{
    __m128i state = _mm_xor_si128(value, keys[0]);
    if (decrypt) {
        for (unsigned round = 1; round < 14; ++round)
            state = _mm_aesdec_si128(state, keys[round]);
        return _mm_aesdeclast_si128(state, keys[14]);
    }
    for (unsigned round = 1; round < 14; ++round)
        state = _mm_aesenc_si128(state, keys[round]);
    return _mm_aesenclast_si128(state, keys[14]);
}

static inline __m128i xex_one(__m128i value, __m128i tweak, const __m128i keys[15], int decrypt)
{
    return _mm_xor_si128(aes_one(_mm_xor_si128(value, tweak), keys, decrypt), tweak);
}

static inline __m128i crypt_four(const unsigned char *input, unsigned char *output,
                                 __m128i tweak, const __m128i keys[15], int decrypt)
{
    __m128i tweaks[4];
    __m128i state[4];
    for (unsigned lane = 0; lane < 4; ++lane) {
        tweaks[lane] = tweak;
        tweak = next_tweak(tweak);
        state[lane] = _mm_xor_si128(_mm_xor_si128(_mm_loadu_si128((const __m128i *)(input + 16 * lane)),
                                                tweaks[lane]), keys[0]);
    }
    if (decrypt) {
        for (unsigned round = 1; round < 14; ++round)
            for (unsigned lane = 0; lane < 4; ++lane)
                state[lane] = _mm_aesdec_si128(state[lane], keys[round]);
        for (unsigned lane = 0; lane < 4; ++lane)
            state[lane] = _mm_aesdeclast_si128(state[lane], keys[14]);
    } else {
        for (unsigned round = 1; round < 14; ++round)
            for (unsigned lane = 0; lane < 4; ++lane)
                state[lane] = _mm_aesenc_si128(state[lane], keys[round]);
        for (unsigned lane = 0; lane < 4; ++lane)
            state[lane] = _mm_aesenclast_si128(state[lane], keys[14]);
    }
    for (unsigned lane = 0; lane < 4; ++lane)
        _mm_storeu_si128((__m128i *)(output + 16 * lane), _mm_xor_si128(state[lane], tweaks[lane]));
    return tweak;
}

#if XTS_MODEL != 0
#if XTS_MODEL == 2
#define ROUND_ATTRIBUTES __attribute__((target("vaes,avx2"), noinline))
#else
#define ROUND_ATTRIBUTES __attribute__((target("vaes,avx2"), always_inline)) inline
#endif

static ROUND_ATTRIBUTES void vaes_rounds(__m256i state[4], const __m128i keys[15], int decrypt)
{
    __m256i initial = _mm256_broadcastsi128_si256(keys[0]);
    __m256i final = _mm256_broadcastsi128_si256(keys[14]);
    __m256i first = _mm256_xor_si256(state[0], initial);
    __m256i second = _mm256_xor_si256(state[1], initial);
    __m256i third = _mm256_xor_si256(state[2], initial);
    __m256i fourth = _mm256_xor_si256(state[3], initial);
    if (decrypt) {
        for (unsigned round = 1; round < 14; ++round) {
            __m256i key = _mm256_broadcastsi128_si256(keys[round]);
            first = _mm256_aesdec_epi128(first, key);
            second = _mm256_aesdec_epi128(second, key);
            third = _mm256_aesdec_epi128(third, key);
            fourth = _mm256_aesdec_epi128(fourth, key);
        }
        state[0] = _mm256_aesdeclast_epi128(first, final);
        state[1] = _mm256_aesdeclast_epi128(second, final);
        state[2] = _mm256_aesdeclast_epi128(third, final);
        state[3] = _mm256_aesdeclast_epi128(fourth, final);
    } else {
        for (unsigned round = 1; round < 14; ++round) {
            __m256i key = _mm256_broadcastsi128_si256(keys[round]);
            first = _mm256_aesenc_epi128(first, key);
            second = _mm256_aesenc_epi128(second, key);
            third = _mm256_aesenc_epi128(third, key);
            fourth = _mm256_aesenc_epi128(fourth, key);
        }
        state[0] = _mm256_aesenclast_epi128(first, final);
        state[1] = _mm256_aesenclast_epi128(second, final);
        state[2] = _mm256_aesenclast_epi128(third, final);
        state[3] = _mm256_aesenclast_epi128(fourth, final);
    }
}

__attribute__((target("vaes,avx2"), noinline))
static __m128i crypt_eight(const unsigned char *input, unsigned char *output,
                          size_t wide_size, __m128i tweak, const __m128i keys[15], int decrypt)
{
    for (size_t offset = 0; offset < wide_size; offset += 128) {
        __m256i tweaks[4];
        __m256i state[4];
        for (unsigned lane = 0; lane < 4; ++lane) {
            __m128i next = next_tweak(tweak);
            tweaks[lane] = _mm256_set_m128i(next, tweak);
            tweak = next_tweak(next);
            state[lane] = _mm256_xor_si256(_mm256_loadu_si256((const __m256i *)(input + offset + 32 * lane)),
                                           tweaks[lane]);
        }
        vaes_rounds(state, keys, decrypt);
        for (unsigned lane = 0; lane < 4; ++lane) {
            _mm256_storeu_si256((__m256i *)(output + offset + 32 * lane),
                                _mm256_xor_si256(state[lane], tweaks[lane]));
        }
    }
    return tweak;
}
#endif

__attribute__((noinline))
static void xts(const unsigned char *input, size_t size, unsigned char *output, int decrypt)
{
    __m128i generated[15], reverse[15], tweak_keys[15];
    expand_key(dual_aes_key, generated);
    expand_key(dual_aes_key + 32, tweak_keys);
    __m128i tweak = aes_one(_mm_loadu_si128((const __m128i *)tweak_bytes), tweak_keys, 0);
    const __m128i *keys = generated;
    if (decrypt) {
        invert_schedule(generated, reverse);
        keys = reverse;
    }
    const size_t partial = size % 16;
    const size_t ordinary = ((size / 16) - (partial != 0)) * 16;
    size_t offset = 0;
#if XTS_MODEL != 0
    if (__builtin_cpu_supports("vaes")) {
        offset = ordinary & ~(size_t)127;
        tweak = crypt_eight(input, output, offset, tweak, keys, decrypt);
    }
#endif
    for (; offset + 64 <= ordinary; offset += 64)
        tweak = crypt_four(input + offset, output + offset, tweak, keys, decrypt);
    for (; offset < ordinary; offset += 16) {
        __m128i block = _mm_loadu_si128((const __m128i *)(input + offset));
        _mm_storeu_si128((__m128i *)(output + offset), xex_one(block, tweak, keys, decrypt));
        tweak = next_tweak(tweak);
    }
    if (partial) {
        __m128i next = next_tweak(tweak);
        __m128i full = _mm_loadu_si128((const __m128i *)(input + offset));
        __m128i first_tweak = decrypt ? next : tweak;
        __m128i second_tweak = decrypt ? tweak : next;
        unsigned char stolen[16];
        _mm_storeu_si128((__m128i *)stolen, xex_one(full, first_tweak, keys, decrypt));
        memcpy(output + offset + 16, stolen, partial);
        memcpy(stolen, input + offset + 16, partial);
        __m128i final = _mm_loadu_si128((const __m128i *)stolen);
        _mm_storeu_si128((__m128i *)(output + offset), xex_one(final, second_tweak, keys, decrypt));
    }
}

static uint64_t ticks(clockid_t clock)
{
    struct timespec sample;
    assert(clock_gettime(clock, &sample) == 0);
    return (uint64_t)sample.tv_sec * 1000000000 + sample.tv_nsec;
}

int main(int argc, char **argv)
{
    assert(argc == 6);
    int decrypt = !strcmp(argv[1], "aes-256-xts-decrypt");
    assert(decrypt || !strcmp(argv[1], "aes-256-xts-encrypt"));
    FILE *input = fopen(argv[2], "rb");
    assert(input && fseek(input, 0, SEEK_END) == 0);
    long file_size = ftell(input);
    assert(file_size >= 16 && fseek(input, 0, SEEK_SET) == 0);
    size_t offset = strtoull(argv[5], NULL, 10);
    size_t count = strtoull(argv[4], NULL, 10);
    assert((size_t)file_size >= offset + 16);
    size_t size = (size_t)file_size - offset;
    unsigned char *allocation = malloc((size_t)file_size + 63);
    unsigned char *encrypted = malloc(size);
    assert(allocation && encrypted);
    unsigned char *aligned = (unsigned char *)(((uintptr_t)allocation + 63) & ~(uintptr_t)63);
    assert(fread(aligned, 1, file_size, input) == (size_t)file_size && fclose(input) == 0);
    const unsigned char *source = aligned + offset;
    xts(source, size, encrypted, decrypt);
    uint64_t wall_start = ticks(CLOCK_MONOTONIC);
    uint64_t cpu_start = ticks(CLOCK_PROCESS_CPUTIME_ID);
    for (size_t i = 0; i < count; ++i) {
        xts(source, size, encrypted, decrypt);
        asm volatile("" : : "r" (encrypted) : "memory");
    }
    uint64_t cpu = ticks(CLOCK_PROCESS_CPUTIME_ID) - cpu_start;
    uint64_t wall = ticks(CLOCK_MONOTONIC) - wall_start;
    FILE *output = fopen(argv[3], "wb");
    assert(output && fwrite(encrypted, 1, size, output) == size && fclose(output) == 0);
    free(encrypted);
    free(allocation);
    printf("%" PRIu64 " %" PRIu64 " 1000000000\n", wall, cpu);
    return 0;
}
