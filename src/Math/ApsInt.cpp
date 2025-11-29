#include "pch.h"
#include "Math/ApsInt.h"
#include "Core/Hash.h"

SWC_BEGIN_NAMESPACE()

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

bool ApsInt::same(const ApsInt& other) const
{
    if (unsigned_ != other.unsigned_)
        return false;
    return ApInt::same(other);
}

int ApsInt::compare(const ApsInt& other) const
{
    if (unsigned_ != other.unsigned_)
        return unsigned_ ? -1 : 1;
    return ApInt::compare(other);
}

SWC_END_NAMESPACE()
