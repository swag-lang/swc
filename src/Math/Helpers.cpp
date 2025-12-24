#include "pch.h"
#include "Math/Helpers.h"
#include "Math/ApFloat.h"

SWC_BEGIN_NAMESPACE()
class ApFloat;

namespace Math
{
    void mul64X64(uint64_t a, uint64_t b, uint64_t& lo, uint64_t& hi)
    {
#ifdef __SIZEOF_INT128__
        __uint128_t r = (__uint128_t) a * b;
        lo            = (uint64_t) r;
        hi            = (uint64_t) (r >> 64);

#elif defined(_MSC_VER) && defined(_M_X64)
        lo = _umul128(a, b, &hi);

#else
        uint64_t ha = a >> 32, hb = b >> 32;
        uint64_t la = (uint32_t) a, lb = (uint32_t) b;
        uint64_t hi_tmp, lo_tmp;

        uint64_t rh  = ha * hb;
        uint64_t rm0 = ha * lb;
        uint64_t rm1 = hb * la;
        uint64_t rl  = la * lb;

        uint64_t t = rl + (rm0 << 32);
        uint64_t c = t < rl;
        lo_tmp     = t + (rm1 << 32);
        c += lo_tmp < t;
        hi_tmp = rh + (rm0 >> 32) + (rm1 >> 32) + c;

        lo = lo_tmp;
        hi = hi_tmp;
#endif
    }

    void div128X64(uint64_t hi, uint64_t lo, uint64_t d, uint64_t& q, uint64_t& r)
    {
        SWC_ASSERT(d != 0);

#ifdef __SIZEOF_INT128__
        // Fast path using native 128-bit integer.
        __uint128_t num  = (static_cast<__uint128_t>(hi) << 64) | lo;
        __uint128_t q128 = num / d;
        __uint128_t r128 = num % d;

        // For (2^128-1) / (2^64) the quotient is < 2^64, so it fits.
        q = static_cast<uint64_t>(q128);
        r = static_cast<uint64_t>(r128);

#elif defined(_MSC_VER) && defined(_M_X64)
        q = _udiv128(hi, lo, d, &r);

#else
        // Portable fallback: bit-by-bit restoring division on 128 bits.
        //
        // Conceptually divides (hi<<64 | lo) by d.
        // We maintain 'rem' as the running remainder (up to 64 bits),
        // and shift in bits from 'lo' high-to-low, just like standard
        // long division.
        uint64_t rem   = hi;
        uint64_t qWord = 0;

        for (int bit = 63; bit >= 0; --bit)
        {
            rem = (rem << 1) | ((lo >> bit) & 1u);
            qWord <<= 1;
            if (rem >= d)
            {
                rem -= d;
                qWord |= 1u;
            }
        }

        q = qWord;
        r = rem;
#endif
    }

    ApsInt bitCastToApInt(const ApFloat& src, bool isUnsigned)
    {
        const uint32_t bw = src.bitWidth();

        if (bw == 32)
        {
            const float f = src.asFloat();
            uint32_t    u = 0;
            std::memcpy(&u, &f, sizeof(u));
            return ApsInt(u, 32, isUnsigned);
        }

        if (bw == 64)
        {
            const double d = src.asDouble();
            int64_t      u = 0;
            std::memcpy(&u, &d, sizeof(u));
            return ApsInt(u, 64, isUnsigned);
        }

        SWC_UNREACHABLE();
    }

    ApFloat bitCastToApFloat(const ApsInt& src, uint32_t floatBits)
    {
        SWC_ASSERT(floatBits == 32 || floatBits == 64);
        SWC_ASSERT(src.bitWidth() == floatBits);

        const uint64_t raw = src.asI64();

        if (floatBits == 32)
        {
            const uint32_t u = static_cast<uint32_t>(raw);
            float          f = 0.0f;
            std::memcpy(&f, &u, sizeof(f));
            return ApFloat(f);
        }

        if (floatBits == 64)
        {
            const uint64_t u = raw;
            double         d = 0.0;
            std::memcpy(&d, &u, sizeof(d));
            return ApFloat(d);
        }

        SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE()
