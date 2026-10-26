#include "pch.h"
#include "Support/Math/Sha256.h"
#if defined(_M_X64)
#include <intrin.h>
#endif

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_RC[64] = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

    uint32_t rotr(const uint32_t value, const uint32_t count) { return (value >> count) | (value << (32 - count)); }

#if defined(_M_X64)
    // The SHA extensions run two rounds per instruction, an order of magnitude faster than the
    // portable rounds. The machine-code cache hashes every function's input stream with this.
    bool hasShaExtensions()
    {
        static const bool available = [] {
            int registers[4];
            __cpuid(registers, 0);
            if (registers[0] < 7)
                return false;
            __cpuidex(registers, 7, 0);
            return (registers[1] & (1 << 29)) != 0;
        }();
        return available;
    }

    // Intel's reference schedule. The state lives as ABEF/CDGH pairs across the rounds; each
    // group of four message words is extended from the previous four groups.
    void shaExtensionBlocks(uint32_t state[8], const uint8_t* data, size_t count)
    {
        const __m128i byteSwap = _mm_set_epi64x(0x0c0d0e0f08090a0bull, 0x0405060700010203ull);
        __m128i       lower    = _mm_shuffle_epi32(_mm_loadu_si128(reinterpret_cast<const __m128i*>(&state[0])), 0xB1);
        __m128i       upper    = _mm_shuffle_epi32(_mm_loadu_si128(reinterpret_cast<const __m128i*>(&state[4])), 0x1B);
        __m128i       abef     = _mm_alignr_epi8(lower, upper, 8);
        __m128i       cdgh     = _mm_blend_epi16(upper, lower, 0xF0);
        for (; count; --count, data += 64)
        {
            const __m128i savedAbef = abef;
            const __m128i savedCdgh = cdgh;
            __m128i       message[4];
            for (int group = 0; group < 16; ++group)
            {
                __m128i& words = message[group & 3];
                if (group < 4)
                    words = _mm_shuffle_epi8(_mm_loadu_si128(reinterpret_cast<const __m128i*>(data + group * 16)), byteSwap);
                else
                {
                    const __m128i& previous = message[(group - 1) & 3];
                    const __m128i  shifted  = _mm_alignr_epi8(previous, message[(group - 2) & 3], 4);
                    words                   = _mm_sha256msg2_epu32(_mm_add_epi32(_mm_sha256msg1_epu32(words, message[(group - 3) & 3]), shifted), previous);
                }
                __m128i scheduled = _mm_add_epi32(words, _mm_loadu_si128(reinterpret_cast<const __m128i*>(&K_RC[group * 4])));
                cdgh              = _mm_sha256rnds2_epu32(cdgh, abef, scheduled);
                scheduled         = _mm_shuffle_epi32(scheduled, 0x0E);
                abef              = _mm_sha256rnds2_epu32(abef, cdgh, scheduled);
            }
            abef = _mm_add_epi32(abef, savedAbef);
            cdgh = _mm_add_epi32(cdgh, savedCdgh);
        }
        const __m128i feba = _mm_shuffle_epi32(abef, 0x1B);
        const __m128i dchg = _mm_shuffle_epi32(cdgh, 0xB1);
        _mm_storeu_si128(reinterpret_cast<__m128i*>(&state[0]), _mm_blend_epi16(feba, dchg, 0xF0));
        _mm_storeu_si128(reinterpret_cast<__m128i*>(&state[4]), _mm_alignr_epi8(dchg, feba, 8));
    }
#endif

    struct Sha256State
    {
        uint32_t                h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
        std::array<uint8_t, 64> tail{};
        uint64_t                totalBytes = 0;
        size_t                  used       = 0;

        void blocks(const uint8_t* data, size_t count)
        {
#if defined(_M_X64)
            if (hasShaExtensions())
            {
                shaExtensionBlocks(h, data, count);
                return;
            }
#endif
            for (; count; --count, data += 64)
                portableBlock(data);
        }

        void portableBlock(const uint8_t* data)
        {
            uint32_t w[64];
            for (size_t i = 0; i < 16; ++i)
            {
                w[i] = (static_cast<uint32_t>(data[i * 4]) << 24) |
                       (static_cast<uint32_t>(data[i * 4 + 1]) << 16) |
                       (static_cast<uint32_t>(data[i * 4 + 2]) << 8) |
                       static_cast<uint32_t>(data[i * 4 + 3]);
            }

            for (int i = 16; i < 64; ++i)
            {
                const uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
                const uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
                w[i]              = w[i - 16] + s0 + w[i - 7] + s1;
            }

            uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
            for (int i = 0; i < 64; ++i)
            {
                const uint32_t s1    = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
                const uint32_t ch    = (e & f) ^ (~e & g);
                const uint32_t temp1 = hh + s1 + ch + K_RC[i] + w[i];
                const uint32_t s0    = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
                const uint32_t maj   = (a & b) ^ (a & c) ^ (b & c);
                const uint32_t temp2 = s0 + maj;

                hh = g;
                g  = f;
                f  = e;
                e  = d + temp1;
                d  = c;
                c  = b;
                b  = a;
                a  = temp1 + temp2;
            }

            h[0] += a;
            h[1] += b;
            h[2] += c;
            h[3] += d;
            h[4] += e;
            h[5] += f;
            h[6] += g;
            h[7] += hh;
        }

        void append(std::span<const std::byte> data)
        {
            totalBytes += data.size();
            if (used)
            {
                const size_t count = std::min(tail.size() - used, data.size());
                if (count)
                    std::memcpy(tail.data() + used, data.data(), count);
                used += count;
                data = data.subspan(count);
                if (used != tail.size())
                    return;
                blocks(tail.data(), 1);
                used = 0;
            }
            const size_t whole = data.size() / tail.size();
            blocks(reinterpret_cast<const uint8_t*>(data.data()), whole);
            data = data.subspan(whole * tail.size());
            if (!data.empty())
            {
                std::memcpy(tail.data(), data.data(), data.size());
                used = data.size();
            }
        }

        std::array<uint8_t, 32> finish()
        {
            const uint64_t bitLength = totalBytes * 8;
            tail[used++]             = 0x80;
            if (used > 56)
            {
                std::memset(tail.data() + used, 0, tail.size() - used);
                blocks(tail.data(), 1);
                used = 0;
            }
            std::memset(tail.data() + used, 0, 56 - used);
            for (size_t index = 0; index < 8; ++index)
                tail[63 - index] = static_cast<uint8_t>(bitLength >> (8 * index));
            blocks(tail.data(), 1);
            std::array<uint8_t, 32> out{};
            for (int i = 0; i < 8; ++i)
            {
                out[i * 4 + 0] = static_cast<uint8_t>(h[i] >> 24);
                out[i * 4 + 1] = static_cast<uint8_t>(h[i] >> 16);
                out[i * 4 + 2] = static_cast<uint8_t>(h[i] >> 8);
                out[i * 4 + 3] = static_cast<uint8_t>(h[i]);
            }

            return out;
        }
    };
}

std::array<uint8_t, 32> sha256Parts(const std::initializer_list<std::span<const std::byte>> parts)
{
    Sha256State state;
    for (const auto part : parts)
        state.append(part);
    return state.finish();
}

std::array<uint8_t, 32> sha256(const std::span<const std::byte> data)
{
    return sha256Parts({data});
}

SWC_END_NAMESPACE();
