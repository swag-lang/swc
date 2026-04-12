#pragma once
#include "Support/Math/ApFloat.h"
#include "Support/Math/ApsInt.h"

SWC_BEGIN_NAMESPACE();

namespace Math
{
    void mul64X64(uint64_t a, uint64_t b, uint64_t& lo, uint64_t& hi);
    void div128X64(uint64_t hi, uint64_t lo, uint64_t d, uint64_t& q, uint64_t& r);

    ApFloat bitCastToApFloat(const ApsInt& src, uint32_t floatBits);
    ApsInt  bitCastToApInt(const ApFloat& src, bool isUnsigned);

    static constexpr bool isPowerOfTwo(uint64_t value) noexcept
    {
        return value != 0 && (value & (value - 1)) == 0;
    }

    static constexpr uint32_t integerLog2(uint64_t value) noexcept
    {
        SWC_ASSERT(isPowerOfTwo(value));
        uint32_t index = 0;
        while (value > 1)
        {
            value >>= 1;
            ++index;
        }

        return index;
    }

    static constexpr uint32_t alignUpU32(uint32_t v, uint32_t a) noexcept
    {
        if (!a)
            return v;

        const uint32_t rem = v % a;
        if (!rem)
            return v;

        return v + a - rem;
    }

    static constexpr uint64_t alignUpU64(uint64_t v, uint64_t a) noexcept
    {
        if (!a)
            return v;

        const uint64_t rem = v % a;
        if (!rem)
            return v;

        return v + a - rem;
    }
}

SWC_END_NAMESPACE();
