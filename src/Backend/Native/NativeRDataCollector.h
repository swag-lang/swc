#pragma once
#include "Backend/Micro/MicroRelocation.h"
#include "Compiler/Sema/Constant/ConstantStorageLayout.h"
#include "Support/Core/DataSegment.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class NativeBackendBuilder;
class SymbolFunction;

// Collects the constant-shard allocations that are reachable from emitted native code or globals
// and remaps their internal relocations into the merged .rdata section. Global roots are read
// from the builder's global layout, so it must be built first.
class NativeRDataCollector
{
public:
    explicit NativeRDataCollector(NativeBackendBuilder& builder);
    NativeRDataCollector(const NativeRDataCollector&)            = delete;
    NativeRDataCollector& operator=(const NativeRDataCollector&) = delete;

    Result collectStartupRoots();
    Result collectFunctionRoots();
    Result collectGlobalRoots();
    Result emitCollectedRoots();

private:
    struct ReachableRDataAllocation
    {
        DataSegmentAllocation source;
        Utf8                  ownerName;

        // An equal interned string reached first, whose emitted bytes this one shares.
        const ReachableRDataAllocation* canonical = nullptr;
        // Index of the emitted entry in the builder's allocation list.
        uint32_t emittedIndex = INVALID_REF;
    };

    struct PendingRDataAllocation
    {
        uint32_t                  shardIndex = 0;
        ReachableRDataAllocation* allocation = nullptr;
    };

    Result collectPendingAllocations();
    Result collectCodeRoots(const Utf8& ownerName, std::span<const MicroRelocation> relocations, const SymbolFunction* ownerSymbol = nullptr);
    Result enqueueConstantRelocation(const Utf8& ownerName, const MicroRelocation& relocation);
    Result enqueueSourceOffset(const Utf8& ownerName, uint32_t shardIndex, uint32_t sourceOffset);
    Result emitReachableAllocations();

    NativeBackendBuilder* builder_ = nullptr;
    // Map values remain stable across rehashes; work lists borrow them until emission ends.
    std::array<std::unordered_map<uint32_t, ReachableRDataAllocation>, ConstantStorageLayout::SHARD_COUNT> allocations_;
    // Every reached allocation, in the order the roots reached it, which is the emission order.
    std::vector<PendingRDataAllocation> reachableAllocations_;
    std::vector<PendingRDataAllocation> pending_;
    // Strings are interned per shard, and which shard holds a string depends on compilation
    // scheduling. Each content is emitted once; later copies become aliases of the first.
    std::unordered_map<std::string_view, const ReachableRDataAllocation*> strings_;
    std::vector<PendingRDataAllocation>                                   aliases_;
};

SWC_END_NAMESPACE();
