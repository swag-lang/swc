#pragma once

#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

// Collects the constant-shard allocations that are reachable from emitted native code
// and remaps their internal relocations into the merged .rdata section.
class NativeRDataCollector
{
public:
    explicit NativeRDataCollector(NativeBackendBuilder& builder);

    Result collectAndEmit();

private:
    struct PendingRDataAllocation
    {
        uint32_t shardIndex   = 0;
        uint32_t sourceOffset = 0;
        Utf8     ownerName;
    };

    Result collectRoots();
    Result collectCodeRoots(const Utf8& ownerName, std::span<const MicroRelocation> relocations);
    Result enqueuePointer(const Utf8& ownerName, const void* ptr);
    Result enqueueSourceOffset(const Utf8& ownerName, uint32_t shardIndex, uint32_t sourceOffset);
    Result emitReachableAllocations();

    NativeBackendBuilder*                                                        builder_ = nullptr;
    std::array<std::vector<uint32_t>, ConstantManager::SHARD_COUNT>              reachableOffsets_;
    std::array<std::unordered_set<uint32_t>, ConstantManager::SHARD_COUNT>       seen_;
    std::array<std::unordered_map<uint32_t, Utf8>, ConstantManager::SHARD_COUNT> owners_;
    std::vector<PendingRDataAllocation>                                          pending_;
};

SWC_END_NAMESPACE();
