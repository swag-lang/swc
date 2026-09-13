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

Result NativeRDataCollector::emitCollectedRoots()
{
    SWC_RESULT(collectPendingAllocations());
    return emitReachableAllocations();
}

Result NativeRDataCollector::collectPendingAllocations()
{
    std::vector<DataSegmentRelocation> allocationRelocations;
    while (!pending_.empty())
    {
        const PendingRDataAllocation pending = pending_.back();
        pending_.pop_back();

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
    reachableAllocations_[shardIndex].push_back(&reachable);
    pending_.push_back({shardIndex, &reachable});
    return Result::Continue;
}

Result NativeRDataCollector::emitReachableAllocations()
{
    for (uint32_t shardIndex = 0; shardIndex < ConstantManager::SHARD_COUNT; ++shardIndex)
    {
        auto& reachable = reachableAllocations_[shardIndex];
        std::ranges::sort(reachable, {}, [](const ReachableRDataAllocation* allocation) { return allocation->source.offset; });

        const DataSegment& segment  = builder_->compiler().cstMgr().shardDataSegment(shardIndex);
        auto&              mappings = builder_->rdataAllocationMap[shardIndex];
        mappings.clear();
        mappings.reserve(reachable.size());

        for (const ReachableRDataAllocation* entry : reachable)
        {
            const DataSegmentAllocation& allocation = entry->source;

            const uint32_t emittedOffset = Math::alignUpU32(static_cast<uint32_t>(builder_->mergedRData.bytes.size()), std::max(allocation.align, 1u));
            if (builder_->mergedRData.bytes.size() < emittedOffset)
                builder_->mergedRData.bytes.resize(emittedOffset, std::byte{0});

            const uint32_t insertOffset = static_cast<uint32_t>(builder_->mergedRData.bytes.size());
            SWC_ASSERT(insertOffset == emittedOffset);
            builder_->mergedRData.bytes.resize(insertOffset + allocation.size);

            const auto* sourceBytes = segment.ptr<std::byte>(allocation.offset);
            SWC_ASSERT(sourceBytes != nullptr);
            std::memcpy(builder_->mergedRData.bytes.data() + insertOffset, sourceBytes, allocation.size);

            NativeRDataAllocationMapEntry mapEntry;
            mapEntry.shardIndex    = shardIndex;
            mapEntry.sourceOffset  = allocation.offset;
            mapEntry.size          = allocation.size;
            mapEntry.align         = std::max(allocation.align, 1u);
            mapEntry.emittedOffset = emittedOffset;
            mappings.push_back(mapEntry);
            builder_->rdataAllocations.push_back(mapEntry);
        }
    }

    std::vector<DataSegmentRelocation> allocationRelocations;
    Utf8                              rdataBaseName;
    for (uint32_t shardIndex = 0; shardIndex < ConstantManager::SHARD_COUNT; ++shardIndex)
    {
        const DataSegment& segment     = builder_->compiler().cstMgr().shardDataSegment(shardIndex);
        const auto&        allocations = reachableAllocations_[shardIndex];

        for (size_t i = 0; i < allocations.size(); ++i)
        {
            const DataSegmentAllocation&         allocation = allocations[i]->source;
            const NativeRDataAllocationMapEntry& mapping    = builder_->rdataAllocationMap[shardIndex][i];

            segment.copyRelocations(allocationRelocations, allocation.offset, allocation.size);
            for (const DataSegmentRelocation& relocation : allocationRelocations)
            {
                NativeSectionRelocation record;
                record.offset = mapping.emittedOffset + (relocation.offset - allocation.offset);

                if (relocation.kind == DataSegmentRelocationKind::DataSegmentOffset)
                {
                    const uint32_t targetShardIndex = relocation.targetShardIndex == INVALID_REF ? shardIndex : relocation.targetShardIndex;
                    uint32_t       targetOffset     = 0;
                    if (!builder_->tryMapRDataSourceOffset(targetOffset, targetShardIndex, relocation.targetOffset))
                        return builder_->reportError(DiagnosticId::cmd_err_native_constant_payload_unsupported, Diagnostic::ARG_SYM, allocations[i]->ownerName);

                    if (rdataBaseName.empty())
                        rdataBaseName = nativeScopedSectionBaseSymbol(builder_->compiler(), K_R_DATA_BASE_SYMBOL);
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
    }

    // Allocation objects locate their relocation range by binary search.
    SWC_ASSERT(std::ranges::is_sorted(builder_->mergedRData.relocations, {}, &NativeSectionRelocation::offset));
    return Result::Continue;
}

SWC_END_NAMESPACE();
