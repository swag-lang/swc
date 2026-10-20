#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Math/ApFloat.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(ApFloat_DecimalExponentExtremesKeepRangeDirection)
{
    const std::array mantissas = {ApInt(1, 128), ApInt(12345, 128), ApInt::maxValue(128)};
    for (const ApInt& mantissa : mantissas)
    {
        ApFloat value;
        value.set(mantissa, std::numeric_limits<int64_t>::max());
        if (!value.isInfinity() || value.isNegative())
            return Result::Error;

        value.set(mantissa, std::numeric_limits<int64_t>::min());
        if (!value.isZero() || value.isNegative())
            return Result::Error;
    }

    ApFloat zero;
    zero.set(ApInt(128), std::numeric_limits<int64_t>::max());
    if (!zero.isZero())
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
