#include "pch.h"
#include "Math/ApsInt.h"
#include "Math/Hash.h"

SWC_BEGIN_NAMESPACE()

void ApsInt::add(const ApsInt& rhs, bool& overflow)
{
    SWC_ASSERT(unsigned_ == rhs.unsigned_);
    if (unsigned_)
        ApInt::add(rhs, overflow);
    else
        addSigned(rhs, overflow);
}

void ApsInt::sub(const ApsInt& rhs, bool& overflow)
{
    SWC_ASSERT(unsigned_ == rhs.unsigned_);
    if (unsigned_)
        ApInt::sub(rhs, overflow);
    else
        subSigned(rhs, overflow);
}

void ApsInt::mul(const ApsInt& rhs, bool& overflow)
{
    SWC_ASSERT(unsigned_ == rhs.unsigned_);
    if (unsigned_)
        ApInt::mul(rhs, overflow);
    else
        mulSigned(rhs, overflow);
}

int64_t ApsInt::div(const ApsInt& rhs, bool& overflow)
{
    SWC_ASSERT(unsigned_ == rhs.unsigned_);
    if (unsigned_)
    {
        overflow = false;
        return static_cast<int64_t>(ApInt::div(rhs));
    }

    return divSigned(rhs, overflow);
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

uint32_t ApsInt::hash() const
{
    uint32_t h = ApInt::hash();
    h          = Math::hashCombine(h, unsigned_);
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

Utf8 ApsInt::toString() const
{
    if (unsigned_)
        return ApInt::toString();
    return toSignedString();
}

SWC_END_NAMESPACE()
