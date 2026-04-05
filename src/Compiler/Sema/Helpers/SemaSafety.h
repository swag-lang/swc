#pragma once
#include "Backend/Runtime.h"

SWC_BEGIN_NAMESPACE();

namespace SemaSafety
{
    constexpr uint16_t mask(const Runtime::SafetyWhat what) noexcept
    {
        return static_cast<uint16_t>(what);
    }

    constexpr bool hasMask(const uint16_t maskValue, const Runtime::SafetyWhat what) noexcept
    {
        const uint16_t requestedMask = mask(what);
        if (!requestedMask)
            return true;

        return (maskValue & requestedMask) == requestedMask;
    }
}

SWC_END_NAMESPACE();
