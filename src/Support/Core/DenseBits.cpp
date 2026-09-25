#include "pch.h"
#include "Support/Core/DenseBits.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

bool DenseBits::copyIfChanged(const std::span<uint64_t> outDst, const std::span<const uint64_t> src)
{
    SWC_ASSERT(outDst.size() == src.size());
    bool changed = false;
    for (size_t i = 0; i < outDst.size(); ++i)
    {
        if (outDst[i] == src[i])
            continue;

        outDst[i] = src[i];
        changed = true;
    }
    return changed;
}

SWC_END_NAMESPACE();
