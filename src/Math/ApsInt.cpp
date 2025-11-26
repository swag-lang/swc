#include "pch.h"
#include "Math/ApsInt.h"
#include "Core/Hash.h"

SWC_BEGIN_NAMESPACE()

uint64_t ApsInt::hash() const
{
    auto h = ApInt::hash();
    h      = hash_combine(h, isUnsigned_);
    return h;
}

ApsInt ApsInt::getMinValue(uint32_t bitWidth, bool isUnsigned)
{
    return isUnsigned ? ApsInt(ApInt::getMinValue(bitWidth), true) : ApsInt(getMinSignedValue(bitWidth), false);
}

ApsInt ApsInt::getMaxValue(uint32_t bitWidth, bool isUnsigned)
{
    return isUnsigned ? ApsInt(ApInt::getMaxValue(bitWidth), true) : ApsInt(getMaxSignedValue(bitWidth), false);
}

bool ApsInt::compareValues(const ApsInt& i1, const ApsInt& i2)
{
    if (i1.isUnsigned_ != i2.isUnsigned_)
        return false;
    return ApInt::compareValues(i1, i2);
}

bool ApsInt::isSameValue(const ApsInt& i1, const ApsInt& i2)
{
    return !compareValues(i1, i2);
}

SWC_END_NAMESPACE()
