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

SWC_END_NAMESPACE()
