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

    ApsInt bitCastToApInt(const ApFloat& src)
    {
        const uint32_t bw = src.bitWidth();

        if (bw == 32)
        {
            const float f = src.asFloat();
            uint32_t    u = 0;
            std::memcpy(&u, &f, sizeof(u));
            return ApsInt(static_cast<uint64_t>(u), 32, true);
        }

        if (bw == 64)
        {
            const double d = src.asDouble();
            int64_t      u = 0;
            std::memcpy(&u, &d, sizeof(u));
            return ApsInt(u, 64, true);
        }

        SWC_UNREACHABLE();
    }

    ApFloat bitCastToApFloat(const ApsInt& src, uint32_t floatBits)
    {
        // We only support IEEE 32 and 64.
        // SWC_ASSERT(floatBits == 32 || floatBits == 64);
        // SWC_ASSERT(src.bitWidth() == floatBits);

        const uint64_t raw = src.asU64();

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

};

SWC_END_NAMESPACE()
