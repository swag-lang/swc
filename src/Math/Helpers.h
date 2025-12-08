#pragma once
#include "Math/ApFloat.h"

SWC_BEGIN_NAMESPACE()

namespace Math
{
    void    mul64X64(uint64_t a, uint64_t b, uint64_t& lo, uint64_t& hi);
    ApsInt  bitCastToApInt(const ApFloat& src);
    ApFloat bitCastToApFloat(const ApsInt& src, uint32_t floatBits);
};

SWC_END_NAMESPACE()
