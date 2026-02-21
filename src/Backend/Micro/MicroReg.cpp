#include "pch.h"
#include "Backend/Micro/MicroReg.h"

SWC_BEGIN_NAMESPACE();

bool MicroReg::isSameClass(MicroReg other) const
{
    if (isInt() && other.isInt())
        return true;
    if (isFloat() && other.isFloat())
        return true;
    if (isVirtualInt() && other.isVirtualInt())
        return true;
    if (isVirtualFloat() && other.isVirtualFloat())
        return true;
    return false;
}

SWC_END_NAMESPACE();
