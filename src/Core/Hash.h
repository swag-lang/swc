// ReSharper disable CppInconsistentNaming
// ReSharper disable IdentifierTypo
#pragma once

SWC_BEGIN_NAMESPACE();

// wyhash — tiny, simplified
// Assumptions: 64-bit little-endian; compiler supports __int128.
// Public domain (The Unlicense). Original: https://github.com/wangyi-fudan/wyhash

inline void wymum(uint64_t* a, uint64_t* b)
{
#if defined(__SIZEOF_INT128__)
    __uint128_t r = *a;
    r *= *b;
    *a = (uint64_t) r;
    *b = (uint64_t) (r >> 64);
#elif defined(_MSC_VER) && defined(_M_X64)
    *a = _umul128(*a, *b, b);
#else
    uint64_t ha = *a >> 32, hb = *b >> 32, la = (uint32_t) *a, lb = (uint32_t) *b, hi, lo;
    uint64_t rh = ha * hb, rm0 = ha * lb, rm1 = hb * la, rl = la * lb, t = rl + (rm0 << 32), c = t < rl;
    lo = t + (rm1 << 32);
    c += lo < t;
    hi = rh + (rm0 >> 32) + (rm1 >> 32) + c;
    *a = lo;
    *b = hi;
#endif
}

inline uint64_t wymix(uint64_t a, uint64_t b)
{
    wymum(&a, &b);
    return a ^ b;
}

inline uint64_t wyr8(const uint8_t* p)
{
    uint64_t v;
    memcpy(&v, p, 8);
    return v;
}

inline uint64_t wyr4(const uint8_t* p)
{
    uint32_t v;
    memcpy(&v, p, 4);
    return v;
}

inline uint64_t wyr3(const uint8_t* p, size_t k)
{
    return (static_cast<uint64_t>(p[0]) << 16) | (static_cast<uint64_t>(p[k >> 1]) << 8) | p[k - 1];
}

inline uint64_t wyhash(const void* key, size_t len, uint64_t seed = 0xa0761d6478bd642full)
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

inline uint64_t hash(std::string_view v, uint64_t seed = 0xa0761d6478bd642full)
{
    return wyhash(v.data(), v.size(), seed);
}

SWC_END_NAMESPACE();
