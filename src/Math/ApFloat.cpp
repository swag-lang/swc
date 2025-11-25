#include "pch.h"
#include "Math/ApFloat.h"
#include "Core/hash.h"
#include "Math/ApInt.h"

SWC_BEGIN_NAMESPACE()

bool ApFloat::equals(const ApFloat& other) const
{
    return true;
}

size_t ApFloat::hash() const
{
    return 1;
}

SWC_END_NAMESPACE()
