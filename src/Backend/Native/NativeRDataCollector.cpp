#include "pch.h"
#include "Backend/Native/NativeRDataCollector.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeNames.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Assert.h"

#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

NativeRDataCollector::NativeRDataCollector(NativeBackendBuilder& builder) :
    builder_(&builder)
{
}

Result NativeRDataCollector::collectAndEmit()
{
    SWC_RESULT(collectStartupRoots());
    SWC_RESULT(collectFunctionRoots());
    SWC_RESULT(collectGlobalRoots());
    return emitCollectedRoots();
}

Result NativeRDataCollector::collectStartupRoots()
{
    if (builder_->startup)
        SWC_RESULT(collectCodeRoots(builder_->startup->debugName, builder_->startup->code.codeRelocations));

    return Result::Continue;
}

Result NativeRDataCollector::collectFunctionRoots()
{
    for (const NativeFunctionInfo& info : builder_->functionInfos)
    {
        if (!info.machineCode)
            continue;

        SWC_RESULT(collectCodeRoots(info.debugName, info.machineCode->codeRelocations));
    }

    return Result::Continue;
}

Result NativeRDataCollector::collectGlobalRoots()
{
    const Utf8& ownerName = builder_->scopedSymbolNames().dataBase;
    for (const DataSegmentRelocation& relocation : builder_->compiler().globalInitSegment().copyRelocations())
    {
        if (relocation.kind != DataSegmentRelocationKind::DataSegmentOffset || relocation.targetShardIndex == INVALID_REF)
            continue;

        SWC_RESULT(enqueueSourceOffset(ownerName, relocation.targetShardIndex, relocation.targetOffset));
    }

    return Result::Continue;
}

Result NativeRDataCollector::emitCollectedRoots()
{
    SWC_RESULT(collectPendingAllocations());
    return emitReachableAllocations();
}

Result NativeRDataCollector::collectPendingAllocations()
{
    // First in, first out: an allocation's dependencies are reached after every root, in the
    // order of the allocations that reference them, so the emission order is the reference order.
    std::vector<DataSegmentRelocation> allocationRelocations;
    for (size_t next = 0; next < pending_.size(); ++next)
    {
        const PendingRDataAllocation pending = pending_[next];

        const DataSegment&           segment    = builder_->compiler().cstMgr().shardDataSegment(pending.shardIndex);
        const DataSegmentAllocation& allocation = pending.allocation->source;

        segment.copyRelocations(allocationRelocations, allocation.offset, allocation.size);
        for (const DataSegmentRelocation& relocation : allocationRelocations)
        {
            if (relocation.kind != DataSegmentRelocationKind::DataSegmentOffset)
                continue;

            const uint32_t targetShardIndex = relocation.targetShardIndex == INVALID_REF ? pending.shardIndex : relocation.targetShardIndex;
            SWC_RESULT(enqueueSourceOffset(pending.allocation->ownerName, targetShardIndex, relocation.targetOffset));
        }
    }

    pending_.clear();
    return Result::Continue;
}

Result NativeRDataCollector::collectCodeRoots(const Utf8& ownerName, const std::span<const MicroRelocation> relocations)
{
    for (const MicroRelocation& relocation : relocations)
    {
        if (relocation.kind != MicroRelocation::Kind::ConstantAddress)
            continue;

        SWC_RESULT(enqueueConstantRelocation(ownerName, relocation));
    }

    return Result::Continue;
}

Result NativeRDataCollector::enqueueConstantRelocation(const Utf8& ownerName, const MicroRelocation& relocation)
{
    SWC_ASSERT(relocation.kind == MicroRelocation::Kind::ConstantAddress);
    DataSegmentRef sourceRef;
    SWC_RESULT(builder_->resolveConstantSourceRef(sourceRef, ownerName, relocation));
    return enqueueSourceOffset(ownerName, sourceRef.shardIndex, sourceRef.offset);
}

Result NativeRDataCollector::enqueueSourceOffset(const Utf8& ownerName, const uint32_t shardIndex, const uint32_t sourceOffset)
{
    const DataSegment&    segment = builder_->compiler().cstMgr().shardDataSegment(shardIndex);
    DataSegmentAllocation allocation;
    if (!segment.findAllocation(allocation, sourceOffset))
        return builder_->reportError(DiagnosticId::cmd_err_native_constant_payload_unsupported, Diagnostic::ARG_SYM, ownerName);

    const auto [it, inserted] = allocations_[shardIndex].try_emplace(allocation.offset);
    if (!inserted)
        return Result::Continue;

    // Allocation extents are immutable even while startup appends to the segment.
    // Relocations are deliberately read later, when the pending allocation is visited.
    ReachableRDataAllocation& reachable = it->second;
    reachable.source                    = allocation;
    reachable.ownerName                 = ownerName;
    reachableAllocations_.push_back({shardIndex, &reachable});
    pending_.push_back({shardIndex, &reachable});
    return Result::Continue;
}

Result NativeRDataCollector::emitReachableAllocations()
{
    const size_t firstAllocationIndex = builder_->rdataAllocations.size();
    builder_->rdataAllocations.reserve(firstAllocationIndex + reachableAllocations_.size());
    for (auto& mappings : builder_->rdataAllocationMap)
        mappings.clear();

    // Allocations are emitted in the order the roots reached them: functions in emission order
    // with their relocations in code order, globals and startup code, each in a fixed order.
    // Which shard holds a constant, and at which offset, follows the order in which compilation
    // jobs created it; laying the section out by shard and offset made two builds of the same
    // program differ.
    for (const PendingRDataAllocation& entry : reachableAllocations_)
    {
        const DataSegment&           segment    = builder_->compiler().cstMgr().shardDataSegment(entry.shardIndex);
        const DataSegmentAllocation& allocation = entry.allocation->source;

        const uint32_t emittedOffset = Math::alignUpU32(static_cast<uint32_t>(builder_->mergedRData.bytes.size()), std::max(allocation.align, 1u));
        builder_->mergedRData.bytes.resize(emittedOffset + allocation.size);

        const auto* sourceBytes = segment.ptr<std::byte>(allocation.offset);
        SWC_ASSERT(sourceBytes != nullptr);
        const bool zeroFilled = std::ranges::all_of(std::span<const std::byte>{sourceBytes, allocation.size}, [](const std::byte value) { return value == std::byte{}; });
        // resize already zeroed the destination. Keep the result for the
        // object writer instead of scanning the copied bytes a second time.
        if (!zeroFilled)
            std::memcpy(builder_->mergedRData.bytes.data() + emittedOffset, sourceBytes, allocation.size);

        NativeRDataAllocationMapEntry mapEntry;
        mapEntry.shardIndex    = entry.shardIndex;
        mapEntry.sourceOffset  = allocation.offset;
        mapEntry.size          = allocation.size;
        mapEntry.align         = std::max(allocation.align, 1u);
        mapEntry.emittedOffset = emittedOffset;
        mapEntry.zeroFilled    = zeroFilled;
        builder_->rdataAllocationMap[entry.shardIndex].push_back(mapEntry);
        builder_->rdataAllocations.push_back(mapEntry);
    }

    // Source offsets are looked up by binary search.
    for (auto& mappings : builder_->rdataAllocationMap)
        std::ranges::sort(mappings, {}, &NativeRDataAllocationMapEntry::sourceOffset);

    std::vector<DataSegmentRelocation> allocationRelocations;
    Utf8                               rdataBaseName;
    for (size_t allocationIndex = 0; allocationIndex < reachableAllocations_.size(); ++allocationIndex)
    {
        const PendingRDataAllocation& entry      = reachableAllocations_[allocationIndex];
        const DataSegment&            segment    = builder_->compiler().cstMgr().shardDataSegment(entry.shardIndex);
        const DataSegmentAllocation&  allocation = entry.allocation->source;
        // The emission list retains the order above; only the per-shard lookup tables were sorted.
        const NativeRDataAllocationMapEntry& mapping = builder_->rdataAllocations[firstAllocationIndex + allocationIndex];
        SWC_ASSERT(mapping.shardIndex == entry.shardIndex && mapping.sourceOffset == allocation.offset);

        segment.copyRelocations(allocationRelocations, allocation.offset, allocation.size);
        for (const DataSegmentRelocation& relocation : allocationRelocations)
        {
            NativeSectionRelocation record;
            record.offset = mapping.emittedOffset + (relocation.offset - allocation.offset);

            if (relocation.kind == DataSegmentRelocationKind::DataSegmentOffset)
            {
                const uint32_t targetShardIndex = relocation.targetShardIndex == INVALID_REF ? entry.shardIndex : relocation.targetShardIndex;
                uint32_t       targetOffset     = 0;
                if (!builder_->tryMapRDataSourceOffset(targetOffset, targetShardIndex, relocation.targetOffset))
                    return builder_->reportError(DiagnosticId::cmd_err_native_constant_payload_unsupported, Diagnostic::ARG_SYM, entry.allocation->ownerName);

                if (rdataBaseName.empty())
                    rdataBaseName = builder_->scopedSymbolNames().rdataBase;
                record.symbolName = rdataBaseName;
                record.addend     = targetOffset;
                builder_->mergedRData.relocations.push_back(std::move(record));
                continue;
            }

            SWC_ASSERT(relocation.kind == DataSegmentRelocationKind::FunctionSymbol);
            SWC_RESULT(builder_->resolveFunctionSymbolName(record.symbolName, relocation.targetSymbol));
            record.addend = 0;
            builder_->mergedRData.relocations.push_back(std::move(record));
        }
    }

    // Allocation objects locate their relocation range by binary search.
    SWC_ASSERT(std::ranges::is_sorted(builder_->mergedRData.relocations, {}, &NativeSectionRelocation::offset));
    return Result::Continue;
}

SWC_END_NAMESPACE();
