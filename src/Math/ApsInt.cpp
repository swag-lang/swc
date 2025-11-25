#include "pch.h"
#include "Math/ApsInt.h"
#include "Core/Hash.h"

SWC_BEGIN_NAMESPACE()

bool ApsInt::equals(const ApsInt& other) const
{
    if (isSigned_ != other.isSigned_)
        return false;
    return ApInt::equals(other);
}

uint64_t ApsInt::hash() const
{
    auto h = ApInt::hash();
    h      = hash_combine(h, isSigned_);
    return h;
}

ApsInt ApsInt::getMinValue(uint32_t bitWidth, bool isSigned)
{
    ApsInt result(bitWidth, isSigned);
    result.resetToZero();

    // Unsigned minimum = 0
    if (!isSigned)
        return result;

    // Signed two's complement minimum = 1000...000
    result.setBit(bitWidth - 1);
    return result;
}

ApsInt ApsInt::getMaxValue(uint32_t bitWidth, bool isSigned)
{
    SWC_ASSERT(bitWidth > 0);

    ApsInt result(bitWidth, isSigned);
    result.resetToZero();

    if (!isSigned)
    {
        result.setAllBits();
        return result;
    }

    // Signed max = 0111...111 (sign bit clear, all others = 1)
    if (bitWidth == 1)
        return result;
    for (uint32_t i = 0; i < bitWidth - 1; ++i)
        result.setBit(i);
    return result;
}

ApsInt ApsInt::getMinValue() const
{
    return getMinValue(bitWidth(), isSigned_);
}

ApsInt ApsInt::getMaxValue() const
{
    return getMaxValue(bitWidth(), isSigned_);
}

SWC_END_NAMESPACE()
