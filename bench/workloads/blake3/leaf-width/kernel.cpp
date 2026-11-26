#include <cstddef>
#include <cstdint>
#include <cstring>
#include <immintrin.h>

#ifndef LANES
#error LANES must be 4 or 8
#endif

using Word = std::uint32_t;
using Vector = Word __attribute__((vector_size(LANES * sizeof(Word))));
static constexpr Word iv[4] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a};
static constexpr unsigned schedule[7][16] = {
    {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15},
    {2,6,3,10,7,0,4,13,1,11,12,5,9,14,15,8},
    {3,4,10,12,13,2,7,14,6,5,9,0,11,15,8,1},
    {10,7,12,9,14,3,13,15,4,0,11,2,5,8,1,6},
    {12,13,9,11,15,10,14,8,7,2,5,3,0,1,6,4},
    {9,14,11,5,8,12,15,1,13,3,0,10,2,6,4,7},
    {11,15,5,0,1,9,8,6,14,10,2,12,3,4,7,13},
};

template<unsigned N> inline Vector rotate_right(Vector value)
{
    if constexpr (N == 8 || N == 16)
    {
        constexpr unsigned Delta = N / 8;
        const __m128i lanes = _mm_setr_epi8(
            Delta, (Delta+1)%4, (Delta+2)%4, (Delta+3)%4,
            Delta+4, (Delta+1)%4+4, (Delta+2)%4+4, (Delta+3)%4+4,
            Delta+8, (Delta+1)%4+8, (Delta+2)%4+8, (Delta+3)%4+8,
            Delta+12, (Delta+1)%4+12, (Delta+2)%4+12, (Delta+3)%4+12);
#if LANES == 4
        return (Vector)_mm_shuffle_epi8((__m128i)value, lanes);
#else
        return (Vector)_mm256_shuffle_epi8((__m256i)value, _mm256_broadcastsi128_si256(lanes));
#endif
    }
    return (value >> N) | (value << (32 - N));
}

inline void mix(Vector& a, Vector& b, Vector& c, Vector& d, Vector x, Vector y)
{
    a += b + x;
    d = rotate_right<16>(d ^ a);
    c += d;
    b = rotate_right<12>(b ^ c);
    a += b + y;
    d = rotate_right<8>(d ^ a);
    c += d;
    b = rotate_right<7>(b ^ c);
}

template<unsigned Round> inline void round(Vector& a0, Vector& a1, Vector& a2, Vector& a3,
    Vector& b0, Vector& b1, Vector& b2, Vector& b3, Vector& c0, Vector& c1, Vector& c2, Vector& c3,
    Vector& d0, Vector& d1, Vector& d2, Vector& d3, const Vector* words)
{
    constexpr auto index = schedule[Round];
    mix(a0,b0,c0,d0,words[index[0]],words[index[1]]);
    mix(a1,b1,c1,d1,words[index[2]],words[index[3]]);
    mix(a2,b2,c2,d2,words[index[4]],words[index[5]]);
    mix(a3,b3,c3,d3,words[index[6]],words[index[7]]);
    mix(a0,b1,c2,d3,words[index[8]],words[index[9]]);
    mix(a1,b2,c3,d0,words[index[10]],words[index[11]]);
    mix(a2,b3,c0,d1,words[index[12]],words[index[13]]);
    mix(a3,b0,c1,d2,words[index[14]],words[index[15]]);
}

#if LANES == 4
static inline void transpose(Vector* row)
{
    const auto l0 = _mm_unpacklo_epi32((__m128i)row[0], (__m128i)row[1]);
    const auto l1 = _mm_unpacklo_epi32((__m128i)row[2], (__m128i)row[3]);
    const auto h0 = _mm_unpackhi_epi32((__m128i)row[0], (__m128i)row[1]);
    const auto h1 = _mm_unpackhi_epi32((__m128i)row[2], (__m128i)row[3]);
    row[0] = (Vector)_mm_unpacklo_epi64(l0, l1);
    row[1] = (Vector)_mm_unpackhi_epi64(l0, l1);
    row[2] = (Vector)_mm_unpacklo_epi64(h0, h1);
    row[3] = (Vector)_mm_unpackhi_epi64(h0, h1);
}
#else
static inline void transpose(Vector* row)
{
    __m256i low32[4], high32[4];
    for (unsigned i = 0; i < 4; ++i)
    {
        const auto left = (__m256i)row[2*i];
        const auto right = (__m256i)row[2*i+1];
        low32[i] = _mm256_unpacklo_epi32(left, right);
        high32[i] = _mm256_unpackhi_epi32(left, right);
    }
    const __m256i halves[8] = {
        _mm256_unpacklo_epi64(low32[0],low32[1]), _mm256_unpackhi_epi64(low32[0],low32[1]),
        _mm256_unpacklo_epi64(high32[0],high32[1]), _mm256_unpackhi_epi64(high32[0],high32[1]),
        _mm256_unpacklo_epi64(low32[2],low32[3]), _mm256_unpackhi_epi64(low32[2],low32[3]),
        _mm256_unpacklo_epi64(high32[2],high32[3]), _mm256_unpackhi_epi64(high32[2],high32[3]),
    };
    for (unsigned i = 0; i < 4; ++i)
    {
        row[i] = (Vector)_mm256_permute2x128_si256(halves[i], halves[i+4], 0x20);
        row[i+4] = (Vector)_mm256_permute2x128_si256(halves[i], halves[i+4], 0x31);
    }
}
#endif

static inline Vector load(const std::uint8_t* address)
{
    Vector value;
    std::memcpy(&value, address, sizeof(value));
    return value;
}

static void hash_group(const std::uint8_t* input, std::uint64_t first, const Word* key,
                       std::uint8_t flags, std::uint8_t* output)
{
    Vector a0 = Vector{} + key[0], a1 = Vector{} + key[1], a2 = Vector{} + key[2], a3 = Vector{} + key[3];
    Vector b0 = Vector{} + key[4], b1 = Vector{} + key[5], b2 = Vector{} + key[6], b3 = Vector{} + key[7];
    Vector low{}, high{};
    for (unsigned lane = 0; lane < LANES; ++lane)
    {
        low[lane] = static_cast<Word>(first + lane);
        high[lane] = static_cast<Word>((first + lane) >> 32);
    }
    for (unsigned block = 0; block < 16; ++block)
    {
        Vector words[16];
        for (unsigned group = 0; group < 16 / LANES; ++group)
        {
            const auto* bytes = input + block * 64 + group * sizeof(Vector);
            for (unsigned lane = 0; lane < LANES; ++lane)
                words[group * LANES + lane] = load(bytes + lane * 1024);
            transpose(words + group * LANES);
        }

        Vector c0 = Vector{} + iv[0], c1 = Vector{} + iv[1], c2 = Vector{} + iv[2], c3 = Vector{} + iv[3];
        const Word block_flags = flags | (block == 0 ? 1 : 0) | (block == 15 ? 2 : 0);
        Vector d0 = low, d1 = high, d2 = Vector{} + Word{64}, d3 = Vector{} + block_flags;

        round<0>(a0,a1,a2,a3,b0,b1,b2,b3,c0,c1,c2,c3,d0,d1,d2,d3,words);
        round<1>(a0,a1,a2,a3,b0,b1,b2,b3,c0,c1,c2,c3,d0,d1,d2,d3,words);
        round<2>(a0,a1,a2,a3,b0,b1,b2,b3,c0,c1,c2,c3,d0,d1,d2,d3,words);
        round<3>(a0,a1,a2,a3,b0,b1,b2,b3,c0,c1,c2,c3,d0,d1,d2,d3,words);
        round<4>(a0,a1,a2,a3,b0,b1,b2,b3,c0,c1,c2,c3,d0,d1,d2,d3,words);
        round<5>(a0,a1,a2,a3,b0,b1,b2,b3,c0,c1,c2,c3,d0,d1,d2,d3,words);
        round<6>(a0,a1,a2,a3,b0,b1,b2,b3,c0,c1,c2,c3,d0,d1,d2,d3,words);
        a0 ^= c0; a1 ^= c1; a2 ^= c2; a3 ^= c3;
        b0 ^= d0; b1 ^= d1; b2 ^= d2; b3 ^= d3;
    }

    Vector result[8] = {a0,a1,a2,a3,b0,b1,b2,b3};
    for (unsigned group = 0; group < 8 / LANES; ++group)
    {
        auto* row = result + group * LANES;
        transpose(row);
        for (unsigned lane = 0; lane < LANES; ++lane)
            std::memcpy(output + lane * 32 + group * sizeof(Vector), &row[lane], sizeof(Vector));
    }
}

extern "C" void KERNEL(const std::uint8_t* input, std::size_t chunks, std::uint64_t first,
                       const Word* key, std::uint8_t flags, std::uint8_t* output)
{
    for (std::size_t chunk = 0; chunk < chunks; chunk += LANES)
        hash_group(input + chunk * 1024, first + chunk, key, flags, output + chunk * 32);
}
