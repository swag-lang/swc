#pragma once
#include "Backend/Micro/MicroRelocation.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class NativeBackendBuilder;

// Collects the constant-shard allocations that are reachable from emitted native code
// and remaps their internal relocations into the merged .rdata section.
class NativeRDataCollector
{
public:
    explicit NativeRDataCollector(NativeBackendBuilder& builder);
    NativeRDataCollector(const NativeRDataCollector&)            = delete;
    NativeRDataCollector& operator=(const NativeRDataCollector&) = delete;

    Result collectAndEmit();
    Result collectStartupRoots();
    Result collectFunctionRoots();
    Result emitCollectedRoots();

private:
    struct ReachableRDataAllocation
    {
        DataSegmentAllocation source;
        Utf8                  ownerName;
    };

    struct PendingRDataAllocation
    {
        uint32_t                        shardIndex = 0;
        const ReachableRDataAllocation* allocation = nullptr;
    };

    Result collectPendingAllocations();
    Result collectCodeRoots(const Utf8& ownerName, std::span<const MicroRelocation> relocations);
    Result enqueueConstantRelocation(const Utf8& ownerName, const MicroRelocation& relocation);
    Result enqueueSourceOffset(const Utf8& ownerName, uint32_t shardIndex, uint32_t sourceOffset);
    Result emitReachableAllocations();

    NativeBackendBuilder* builder_ = nullptr;
    // Map values remain stable across rehashes; work lists borrow them until emission ends.
    std::array<std::unordered_map<uint32_t, ReachableRDataAllocation>, ConstantManager::SHARD_COUNT> allocations_;
    std::array<std::vector<const ReachableRDataAllocation*>, ConstantManager::SHARD_COUNT>           reachableAllocations_;
    std::vector<PendingRDataAllocation>                                                              pending_;
};

SWC_END_NAMESPACE();
