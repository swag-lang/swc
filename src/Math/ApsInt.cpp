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

void ApsInt::resize(uint32_t newBits)
{
    if (unsigned_)
        resizeUnsigned(newBits);
    else
        resizeSigned(newBits);
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

bool ApsInt::eq(const ApsInt& rhs) const
{
    SWC_ASSERT(unsigned_ == rhs.unsigned_);
    return ApInt::eq(rhs);
}

bool ApsInt::lt(const ApsInt& rhs) const
{
    SWC_ASSERT(unsigned_ == rhs.unsigned_);
    return unsigned_ ? ult(rhs) : slt(rhs);
}

bool ApsInt::le(const ApsInt& rhs) const
{
    SWC_ASSERT(unsigned_ == rhs.unsigned_);
    return unsigned_ ? ule(rhs) : sle(rhs);
}

bool ApsInt::gt(const ApsInt& rhs) const
{
    SWC_ASSERT(unsigned_ == rhs.unsigned_);
    return unsigned_ ? ugt(rhs) : sgt(rhs);
}

bool ApsInt::ge(const ApsInt& rhs) const
{
    SWC_ASSERT(unsigned_ == rhs.unsigned_);
    return unsigned_ ? uge(rhs) : sge(rhs);
}

SWC_END_NAMESPACE()
