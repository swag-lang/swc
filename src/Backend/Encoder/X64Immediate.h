#pragma once

SWC_BEGIN_NAMESPACE();

namespace X64Immediate
{
    inline bool canEncodeSigned32(uint64_t value)
    {
        return value <= 0x7FFFFFFF || value >= 0xFFFFFFFF80000000;
    }
}

SWC_END_NAMESPACE();
