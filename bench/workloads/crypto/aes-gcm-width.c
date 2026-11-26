#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <immintrin.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    __m128i low, high, cross;
} Product128;

static inline __m128i byte_reverse(__m128i x)
{
    return _mm_shuffle_epi8(x, _mm_setr_epi8(15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0));
}

static inline __m128i prepare_key(__m128i key)
{
    const __m128i reciprocal = _mm_set_epi64x((uint64_t)0xc200000000000000ULL, 1);
    __m128i reversed = byte_reverse(key);
    __m128i carry = _mm_srli_epi64(reversed, 63);
    __m128i mask = _mm_sub_epi64(_mm_setzero_si128(), _mm_shuffle_epi32(carry, 0xee));
    __m128i doubled = _mm_or_si128(_mm_slli_epi64(reversed, 1), _mm_slli_si128(carry, 8));
    return _mm_xor_si128(doubled, _mm_and_si128(mask, reciprocal));
}

static inline void add128(Product128 *p, __m128i value, __m128i key)
{
    p->low = _mm_xor_si128(p->low, _mm_clmulepi64_si128(value, key, 0));
    p->high = _mm_xor_si128(p->high, _mm_clmulepi64_si128(value, key, 17));
    __m128i mixed = _mm_xor_si128(_mm_clmulepi64_si128(value, key, 1), _mm_clmulepi64_si128(value, key, 16));
    p->cross = _mm_xor_si128(p->cross, mixed);
}

static inline __m128i reduce128(Product128 p)
{
    const __m128i poly = _mm_set_epi64x(0, (uint64_t)0xc200000000000000ULL);
    __m128i low = _mm_xor_si128(p.low, _mm_slli_si128(p.cross, 8));
    __m128i high = _mm_xor_si128(p.high, _mm_srli_si128(p.cross, 8));
    __m128i correction = _mm_clmulepi64_si128(low, poly, 0);
    __m128i quotient = _mm_xor_si128(low, _mm_slli_si128(correction, 8));
    __m128i second = _mm_clmulepi64_si128(quotient, poly, 1);
    return _mm_xor_si128(_mm_xor_si128(high, low),
                         _mm_xor_si128(_mm_shuffle_epi32(correction, 0x4e), second));
}

static inline __m128i multiply(__m128i value, __m128i key)
{
    Product128 p = {_mm_setzero_si128(), _mm_setzero_si128(), _mm_setzero_si128()};
    add128(&p, value, key);
    return reduce128(p);
}

#ifndef GCM_MODEL
#define GCM_MODEL 0
#endif

static const unsigned char key[32] = "0123456789abcdefghijklmnopqrstuv";
static const unsigned char nonce[16] = "0123456789ab";
static const unsigned char aad[16] = "swag-crypto-1";

typedef struct { __m128i block[4]; } Blocks4;

static inline __m128i next_key(__m128i previous, __m128i substituted)
{
    __m128i pairs = _mm_xor_si128(previous, _mm_slli_si128(previous, 4));
    return _mm_xor_si128(_mm_xor_si128(pairs, _mm_slli_si128(pairs, 8)), substituted);
}

static inline void expand_key(__m128i expanded[15])
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

static inline __m128i counter(__m128i prefix, uint32_t index)
{
    return _mm_insert_epi32(prefix, __builtin_bswap32(index), 3);
}

static inline __m128i aes_one(__m128i value, const __m128i expanded[15])
{
    __m128i state = _mm_xor_si128(value, expanded[0]);
    #pragma GCC unroll 13
    for (unsigned round = 1; round < 14; ++round)
        state = _mm_aesenc_si128(state, expanded[round]);
    return _mm_aesenclast_si128(state, expanded[14]);
}

static inline Blocks4 aes_four_begin(__m128i prefix, uint32_t first, __m128i initial)
{
    Blocks4 state;
    for (unsigned lane = 0; lane < 4; ++lane)
        state.block[lane] = _mm_xor_si128(counter(prefix, first + lane), initial);
    return state;
}

static inline void aes_four_round(Blocks4 *state, __m128i round_key)
{
    for (unsigned lane = 0; lane < 4; ++lane)
        state->block[lane] = _mm_aesenc_si128(state->block[lane], round_key);
}

static inline void aes_four_finish(Blocks4 *state, __m128i final,
                                   const unsigned char *src, unsigned char *dst)
{
    for (unsigned lane = 0; lane < 4; ++lane) {
        __m128i input = _mm_loadu_si128((const __m128i *)(src + 16 * lane));
        state->block[lane] = _mm_xor_si128(input, _mm_aesenclast_si128(state->block[lane], final));
        _mm_storeu_si128((__m128i *)(dst + 16 * lane), state->block[lane]);
    }
}

static inline Blocks4 encrypt_four(__m128i prefix, uint32_t first, const __m128i keys[15],
                                   const unsigned char *src, unsigned char *dst)
{
    Blocks4 state = aes_four_begin(prefix, first, keys[0]);
    #pragma GCC unroll 13
    for (unsigned round = 1; round < 14; ++round)
        aes_four_round(&state, keys[round]);
    aes_four_finish(&state, keys[14], src, dst);
    return state;
}

static inline __m128i authenticate_four(__m128i state, Blocks4 data, const __m128i powers[4])
{
    Product128 products = {_mm_setzero_si128(), _mm_setzero_si128(), _mm_setzero_si128()};
    add128(&products, _mm_xor_si128(state, byte_reverse(data.block[0])), powers[3]);
    for (unsigned lane = 1; lane < 4; ++lane)
        add128(&products, byte_reverse(data.block[lane]), powers[3 - lane]);
    return reduce128(products);
}

static inline __m128i authenticate_encrypted_blocks(__m128i state, const unsigned char *src,
                                                   size_t size, const __m128i powers[4])
{
    for (size_t offset = 0; offset < size; offset += 64) {
        Blocks4 batch;
        for (unsigned lane = 0; lane < 4; ++lane)
            batch.block[lane] = _mm_loadu_si128((const __m128i *)(src + offset + 16 * lane));
        state = authenticate_four(state, batch, powers);
    }
    return state;
}

#if GCM_MODEL >= 3
typedef struct { __m256i pair[4]; } Blocks8;
typedef struct { __m256i low, high, cross; } WideProducts;

static inline Blocks8 aes_eight_begin(__m128i prefix, uint32_t first, __m128i initial)
{
    Blocks8 state;
    __m256i key = _mm256_broadcastsi128_si256(initial);
    for (unsigned lane = 0; lane < 4; ++lane) {
        __m128i low = counter(prefix, first + 2 * lane);
        __m128i high = counter(prefix, first + 2 * lane + 1);
        state.pair[lane] = _mm256_xor_si256(_mm256_set_m128i(high, low), key);
    }
    return state;
}

static inline void aes_eight_round(Blocks8 *state, __m128i round_key)
{
    __m256i key = _mm256_broadcastsi128_si256(round_key);
    for (unsigned lane = 0; lane < 4; ++lane)
        state->pair[lane] = _mm256_aesenc_epi128(state->pair[lane], key);
}

static inline void aes_eight_finish(Blocks8 *state, __m128i final,
                                    const unsigned char *src, unsigned char *dst)
{
    __m256i key = _mm256_broadcastsi128_si256(final);
    for (unsigned lane = 0; lane < 4; ++lane) {
        __m256i input = _mm256_loadu_si256((const __m256i *)(src + 32 * lane));
        state->pair[lane] = _mm256_xor_si256(input, _mm256_aesenclast_epi128(state->pair[lane], key));
        _mm256_storeu_si256((__m256i *)(dst + 32 * lane), state->pair[lane]);
    }
}

static inline Blocks8 encrypt_eight(__m128i prefix, uint32_t first, const __m128i keys[15],
                                    const unsigned char *src, unsigned char *dst)
{
    Blocks8 state = aes_eight_begin(prefix, first, keys[0]);
    #pragma GCC unroll 13
    for (unsigned round = 1; round < 14; ++round)
        aes_eight_round(&state, keys[round]);
    aes_eight_finish(&state, keys[14], src, dst);
    return state;
}

static inline __m256i reverse_pairs(__m256i x)
{
    __m128i mask = _mm_setr_epi8(15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0);
    return _mm256_shuffle_epi8(x, _mm256_broadcastsi128_si256(mask));
}

static inline void add_wide(WideProducts *p, __m256i value, __m256i power)
{
    p->low = _mm256_xor_si256(p->low, _mm256_clmulepi64_epi128(value, power, 0));
    p->high = _mm256_xor_si256(p->high, _mm256_clmulepi64_epi128(value, power, 17));
    __m256i mix = _mm256_xor_si256(_mm256_clmulepi64_epi128(value, power, 1),
                                  _mm256_clmulepi64_epi128(value, power, 16));
    p->cross = _mm256_xor_si256(p->cross, mix);
}

static inline __m128i reduce_wide_lanes(__m256i pair)
{
    return _mm_xor_si128(_mm256_castsi256_si128(pair), _mm256_extracti128_si256(pair, 1));
}

static inline __m128i reduce_wide(WideProducts products)
{
    Product128 p = {reduce_wide_lanes(products.low), reduce_wide_lanes(products.high),
                    reduce_wide_lanes(products.cross)};
    return reduce128(p);
}

static inline __m128i authenticate_eight(__m128i auth, Blocks8 data, const __m256i powers[4])
{
    const __m256i zero = _mm256_setzero_si256();
    WideProducts p = {zero, zero, zero};
    __m256i first = _mm256_xor_si256(reverse_pairs(data.pair[0]),
                                    _mm256_set_m128i(_mm_setzero_si128(), auth));
    add_wide(&p, first, powers[0]);
    for (unsigned lane = 1; lane < 4; ++lane)
        add_wide(&p, reverse_pairs(data.pair[lane]), powers[lane]);
    return reduce_wide(p);
}

static __m128i process_wide(__m128i auth, __m128i prefix, const __m128i keys[15], __m128i key,
                            const unsigned char *source, unsigned char *out, size_t size)
{
    __m128i powers[8];
    powers[0] = key;
    for (unsigned i = 1; i < 8; ++i)
        powers[i] = multiply(powers[(i - 1) / 2], powers[i / 2]);
    __m256i pairs[4];
    for (unsigned i = 0; i < 4; ++i)
        pairs[i] = _mm256_set_m128i(powers[6 - 2 * i], powers[7 - 2 * i]);
#if GCM_MODEL == 5
    for (size_t offset = 0; offset < size; offset += 128)
        encrypt_eight(prefix, (uint32_t)(offset / 16 + 2), keys, source + offset, out + offset);
    for (size_t offset = 0; offset < size; offset += 128) {
        Blocks8 data;
        for (unsigned lane = 0; lane < 4; ++lane)
            data.pair[lane] = _mm256_loadu_si256((const __m256i *)(out + offset + 32 * lane));
        auth = authenticate_eight(auth, data, pairs);
    }
    return auth;
#else
    Blocks8 previous = encrypt_eight(prefix, 2, keys, source, out);
    for (size_t offset = 128; offset < size; offset += 128) {
        Blocks8 next = aes_eight_begin(prefix, (uint32_t)(offset / 16 + 2), keys[0]);
        const __m256i zero = _mm256_setzero_si256();
        WideProducts products = {zero, zero, zero};
#if GCM_MODEL == 4
        asm volatile("" : "+m" (previous), "+m" (next), "+m" (pairs) : : "memory");
#endif
        #pragma GCC unroll 13
        for (unsigned round = 1; round < 14; ++round) {
            aes_eight_round(&next, keys[round]);
            switch (round) {
            case 1:
                add_wide(&products, _mm256_xor_si256(reverse_pairs(previous.pair[0]),
                                                    _mm256_set_m128i(_mm_setzero_si128(), auth)), pairs[0]);
                break;
            case 3:
                add_wide(&products, reverse_pairs(previous.pair[1]), pairs[1]);
                break;
            case 5:
                add_wide(&products, reverse_pairs(previous.pair[2]), pairs[2]);
                break;
            case 7:
                add_wide(&products, reverse_pairs(previous.pair[3]), pairs[3]);
                break;
            default:
                break;
            }
        }
        auth = reduce_wide(products);
        aes_eight_finish(&next, keys[14], source + offset, out + offset);
        previous = next;
    }
    return authenticate_eight(auth, previous, pairs);
#endif
}
#endif

__attribute__((noinline))
static void seal(const unsigned char *source, size_t size, unsigned char *out)
{
    __m128i keys[15];
    expand_key(keys);
    __m128i prefix = _mm_loadu_si128((const __m128i *)nonce);
    __m128i powers[4];
    powers[0] = prepare_key(aes_one(_mm_setzero_si128(), keys));
    __m128i auth = multiply(byte_reverse(_mm_loadu_si128((const __m128i *)aad)), powers[0]);
    size_t full_batches = size & ~(size_t)63;
    size_t offset = 0;
#if GCM_MODEL >= 3
    if (size >= 128 && __builtin_cpu_supports("vaes") && __builtin_cpu_supports("vpclmulqdq")) {
        const size_t wide_size = size & ~(size_t)127;
        auth = process_wide(auth, prefix, keys, powers[0], source, out, wide_size);
        offset = wide_size;
    }
#endif
    if (offset < full_batches) {
        powers[1] = multiply(powers[0], powers[0]);
        powers[2] = multiply(powers[1], powers[0]);
        powers[3] = multiply(powers[1], powers[1]);
#if GCM_MODEL == 0
        for (; offset < full_batches; offset += 64)
            encrypt_four(prefix, (uint32_t)(offset / 16 + 2), keys, source + offset, out + offset);
        auth = authenticate_encrypted_blocks(auth, out, full_batches, powers);
#elif GCM_MODEL == 1
        for (; offset < full_batches; offset += 64) {
            Blocks4 data = encrypt_four(prefix, (uint32_t)(offset / 16 + 2), keys, source + offset, out + offset);
            auth = authenticate_four(auth, data, powers);
        }
#elif GCM_MODEL >= 2
        Blocks4 previous = encrypt_four(prefix, (uint32_t)(offset / 16 + 2), keys, source + offset, out + offset);
        for (offset += 64; offset < full_batches; offset += 64) {
            Blocks4 next = aes_four_begin(prefix, (uint32_t)(offset / 16 + 2), keys[0]);
            Product128 products = {_mm_setzero_si128(), _mm_setzero_si128(), _mm_setzero_si128()};
            #pragma GCC unroll 13
            for (unsigned round = 1; round < 14; ++round) {
                aes_four_round(&next, keys[round]);
                switch (round) {
                case 1:
                    add128(&products, _mm_xor_si128(auth, byte_reverse(previous.block[0])), powers[3]);
                    break;
                case 3:
                    add128(&products, byte_reverse(previous.block[1]), powers[2]);
                    break;
                case 5:
                    add128(&products, byte_reverse(previous.block[2]), powers[1]);
                    break;
                case 7:
                    add128(&products, byte_reverse(previous.block[3]), powers[0]);
                    break;
                default:
                    break;
                }
            }
            auth = reduce128(products);
            aes_four_finish(&next, keys[14], source + offset, out + offset);
            previous = next;
        }
        auth = authenticate_four(auth, previous, powers);
#endif
    }

    for (; offset + 16 <= size; offset += 16) {
        __m128i stream = aes_one(counter(prefix, (uint32_t)(offset / 16 + 2)), keys);
        __m128i data = _mm_xor_si128(stream, _mm_loadu_si128((const __m128i *)(source + offset)));
        _mm_storeu_si128((__m128i *)(out + offset), data);
        auth = multiply(_mm_xor_si128(auth, byte_reverse(data)), powers[0]);
    }
    if (offset < size) {
        unsigned char tail[16] = {0};
        __m128i stream = aes_one(counter(prefix, (uint32_t)(offset / 16 + 2)), keys);
        memcpy(tail, source + offset, size - offset);
        __m128i data = _mm_xor_si128(stream, _mm_loadu_si128((const __m128i *)tail));
        _mm_storeu_si128((__m128i *)tail, data);
        memcpy(out + offset, tail, size - offset);
        memset(tail + size - offset, 0, 16 - (size - offset));
        auth = multiply(_mm_xor_si128(auth, byte_reverse(_mm_loadu_si128((const __m128i *)tail))), powers[0]);
    }

    __m128i lengths = _mm_set_epi64x((sizeof("swag-crypto-1") - 1) * 8, size * 8);
    auth = byte_reverse(multiply(_mm_xor_si128(auth, lengths), powers[0]));
    __m128i tag = _mm_xor_si128(auth, aes_one(counter(prefix, 1), keys));
    _mm_storeu_si128((__m128i *)(out + size), tag);
}

static uint64_t ticks(clockid_t clock)
{
    struct timespec sample;
    assert(clock_gettime(clock, &sample) == 0);
    return (uint64_t)sample.tv_sec * 1000000000 + sample.tv_nsec;
}

int main(int argc, char **argv)
{
    assert(argc == 6 && !strcmp(argv[1], "aes-256-gcm"));
    FILE *input = fopen(argv[2], "rb");
    assert(input && fseek(input, 0, SEEK_END) == 0);
    long file_size = ftell(input);
    assert(file_size >= 0 && fseek(input, 0, SEEK_SET) == 0);
    size_t offset = strtoull(argv[5], NULL, 10);
    size_t count = strtoull(argv[4], NULL, 10);
    assert((size_t)file_size >= offset);
    size_t size = (size_t)file_size - offset;
    unsigned char *allocation = malloc((size_t)file_size + 63);
    unsigned char *encrypted = malloc(size + 16);
    assert(allocation && encrypted);
    unsigned char *aligned = (unsigned char *)(((uintptr_t)allocation + 63) & ~(uintptr_t)63);
    assert(fread(aligned, 1, file_size, input) == (size_t)file_size && fclose(input) == 0);
    const unsigned char *source = aligned + offset;
    seal(source, size, encrypted);
    uint64_t wall_start = ticks(CLOCK_MONOTONIC);
    uint64_t cpu_start = ticks(CLOCK_PROCESS_CPUTIME_ID);
    for (size_t i = 0; i < count; ++i) {
        seal(source, size, encrypted);
        asm volatile("" : : "r" (encrypted) : "memory");
    }
    uint64_t cpu = ticks(CLOCK_PROCESS_CPUTIME_ID) - cpu_start;
    uint64_t wall = ticks(CLOCK_MONOTONIC) - wall_start;
    FILE *output = fopen(argv[3], "wb");
    assert(output && fwrite(encrypted, 1, size + 16, output) == size + 16 && fclose(output) == 0);
    free(encrypted);
    free(allocation);
    printf("%" PRIu64 " %" PRIu64 " 1000000000\n", wall, cpu);
    return 0;
}
