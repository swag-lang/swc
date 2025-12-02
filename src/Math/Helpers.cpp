#include "pch.h"
#include "Math/Helpers.h"

SWC_BEGIN_NAMESPACE()

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
};

SWC_END_NAMESPACE()
