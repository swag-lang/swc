#pragma once
#include <cstdint>

SWC_BEGIN_NAMESPACE();

namespace ConstantShardPreference
{
    inline bool mergeRequiredShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, uint32_t candidateShardIndex)
    {
        if (!hasRequiredShard)
        {
            outShardIndex    = candidateShardIndex;
            hasRequiredShard = true;
        }

        // Payload materialization can now relocate across shards, so this is
        // only a placement preference for the owning allocation.
        return true;
    }
}

SWC_END_NAMESPACE();
