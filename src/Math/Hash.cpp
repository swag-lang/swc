#include "pch.h"
#include "Math/Hash.h"
#include "Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

// wyhash — tiny, simplified
// Assumptions: 64-bit little-endian; compiler supports __int128.
// Public domain (The Unlicense). Original: https://github.com/wangyi-fudan/wyhash

namespace
{
    void wymum(uint64_t* a, uint64_t* b)
    {
        uint64_t lo, hi;
        Math::mul64X64(*a, *b, lo, hi);
        *a = lo;
        *b = hi;
    }

    uint64_t wymix(uint64_t a, uint64_t b)
    {
        wymum(&a, &b);
        return a ^ b;
    }

    uint64_t wyr8(const uint8_t* p)
    {
        uint64_t v;
        memcpy(&v, p, 8);
        return v;
    }

    uint64_t wyr4(const uint8_t* p)
    {
        uint32_t v;
        memcpy(&v, p, 4);
        return v;
    }

    uint64_t wyr3(const uint8_t* p, size_t k)
    {
        return (static_cast<uint64_t>(p[0]) << 16) | (static_cast<uint64_t>(p[k >> 1]) << 8) | p[k - 1];
    }

    uint64_t wyhash(const void* key, size_t len, uint64_t seed = 0xa0761d6478bd642full)
    {
        static constexpr uint64_t SECRET[4] = {
            0x2d358dccaa6c78a5ull, 0x8bb84b93962eacc9ull,
            0x4b33a62ed433d4a3ull, 0x4d5a2da51de1aa47ull};

        auto p = static_cast<const uint8_t*>(key);
        seed ^= wymix(seed ^ SECRET[0], SECRET[1]);

        uint64_t a, b;
        if (len <= 16)
        {
            if (len >= 4)
            {
                a = (wyr4(p) << 32) | wyr4(p + ((len >> 3) << 2));
                b = (wyr4(p + len - 4) << 32) | wyr4(p + len - 4 - ((len >> 3) << 2));
            }
            else if (len)
            {
                a = wyr3(p, len);
                b = 0;
            }
            else
            {
                a = b = 0;
            }
        }
        else
        {
            size_t i = len;
            if (i >= 48)
            {
                uint64_t s1 = seed, s2 = seed;
                do
                {
                    seed = wymix(wyr8(p) ^ SECRET[1], wyr8(p + 8) ^ seed);
                    s1   = wymix(wyr8(p + 16) ^ SECRET[2], wyr8(p + 24) ^ s1);
                    s2   = wymix(wyr8(p + 32) ^ SECRET[3], wyr8(p + 40) ^ s2);
                    p += 48;
                    i -= 48;
                } while (i >= 48);
                seed ^= s1 ^ s2;
            }
            while (i > 16)
            {
                seed = wymix(wyr8(p) ^ SECRET[1], wyr8(p + 8) ^ seed);
                p += 16;
                i -= 16;
            }
            a = wyr8(p + i - 16);
            b = wyr8(p + i - 8);
        }

        a ^= SECRET[1];
        b ^= seed;
        wymum(&a, &b);
        return wymix(a ^ SECRET[0] ^ len, b ^ SECRET[1]);
    }
}

namespace Math
{
    uint32_t hash(std::string_view v, uint64_t seed)
    {
        return wyhash(v.data(), v.size(), seed) & 0xFFFFFFFF;
    }

    uint32_t hash(ByteSpan v, uint64_t seed)
    {
        if (!v.data())
            return 0;
        return wyhash(v.data(), v.size(), seed) & 0xFFFFFFFF;
    }

    uint32_t hash(uint32_t v)
    {
        v ^= v >> 16;
        v *= 0x7feb352d;
        v ^= v >> 15;
        v *= 0x846ca68b;
        v ^= v >> 16;
        return v;
    }

    uint32_t hashCombine(uint32_t h, bool v)
    {
        return hashCombine(h, static_cast<uint32_t>(v));
    }

    uint32_t hashCombine(uint32_t h, uint32_t v)
    {
        constexpr uint32_t k = 0x9e3779b9u;
        h ^= v + k + (h << 6) + (h >> 2);
        return h;
    }

    uint32_t hashCombine(uint32_t h, uint64_t v)
    {
        const uint32_t     folded = static_cast<uint32_t>(v) ^ static_cast<uint32_t>(v >> 32);
        constexpr uint32_t k      = 0x9e3779b9u;
        h ^= folded + k + (h << 6) + (h >> 2);
        return h;
    }
}

SWC_END_NAMESPACE();
