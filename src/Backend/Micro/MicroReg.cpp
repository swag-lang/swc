#include "pch.h"
#include "Backend/Micro/MicroReg.h"

SWC_BEGIN_NAMESPACE();

bool MicroReg::isSameClass(MicroReg other) const
{
    if (isAnyInt() && other.isAnyInt())
        return true;
    if (isAnyFloat() && other.isAnyFloat())
        return true;
    return false;
}

SWC_END_NAMESPACE();
