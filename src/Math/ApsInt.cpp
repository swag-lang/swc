#include "pch.h"
#include "Math/ApsInt.h"
#include "Core/Hash.h"

SWC_BEGIN_NAMESPACE()

bool ApsInt::same(const ApsInt& other) const
{
    if (unsigned_ != other.unsigned_)
        return false;
    return ApInt::same(other);
}

uint64_t ApsInt::hash() const
{
    auto h = ApInt::hash();
    h      = hash_combine(h, unsigned_);
    return h;
}

ApsInt ApsInt::minValue(uint32_t bitWidth, bool isUnsigned)
{
    return isUnsigned ? ApsInt(ApInt::minValue(bitWidth), true) : ApsInt(minSignedValue(bitWidth), false);
}

ApsInt ApsInt::maxValue(uint32_t bitWidth, bool isUnsigned)
{
    return isUnsigned ? ApsInt(ApInt::maxValue(bitWidth), true) : ApsInt(maxSignedValue(bitWidth), false);
}

bool ApsInt::compareValues(const ApsInt& i1, const ApsInt& i2)
{
    if (i1.unsigned_ != i2.unsigned_)
        return false;
    return ApInt::compareValues(i1, i2);
}

bool ApsInt::isSameValue(const ApsInt& i1, const ApsInt& i2)
{
    return !compareValues(i1, i2);
}

SWC_END_NAMESPACE()
