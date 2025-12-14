#pragma once
#include "Math/ApFloat.h"
#include "Math/ApsInt.h"

SWC_BEGIN_NAMESPACE()

namespace Math
{
    void mul64X64(uint64_t a, uint64_t b, uint64_t& lo, uint64_t& hi);
    void div128X64(uint64_t hi, uint64_t lo, uint64_t d, uint64_t& q, uint64_t& r);

    ApFloat bitCastToApFloat(const ApsInt& src, uint32_t floatBits);
    ApsInt  bitCastToApInt(const ApFloat& src, bool isUnsigned);
};

SWC_END_NAMESPACE()
