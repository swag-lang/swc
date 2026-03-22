#include "pch.h"
#include "Backend/Native/NativeRDataCollector.h"

#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

NativeRDataCollector::NativeRDataCollector(NativeBackendBuilder& builder) :
    builder_(&builder)
{
}

Result NativeRDataCollector::collectAndEmit()
{
    SWC_RESULT(collectRoots());
    return emitReachableAllocations();
}

Result NativeRDataCollector::collectRoots()
{
    if (builder_->startup)
        SWC_RESULT(collectCodeRoots(builder_->startup->debugName, builder_->startup->code.codeRelocations));

    for (const NativeFunctionInfo& info : builder_->functionInfos)
    {
        if (!info.machineCode)
            continue;

        const Utf8 ownerName = info.symbol ? info.symbol->getFullScopedName(builder_->ctx()) : info.debugName;
        SWC_RESULT(collectCodeRoots(ownerName, info.machineCode->codeRelocations));
    }

    while (!pending_.empty())
    {
        PendingRDataAllocation pending = std::move(pending_.back());
        pending_.pop_back();

        const DataSegment&    segment = builder_->compiler().cstMgr().shardDataSegment(pending.shardIndex);
        DataSegmentAllocation allocation;
        if (!segment.findAllocation(allocation, pending.sourceOffset) || allocation.offset != pending.sourceOffset)
            return builder_->reportError(DiagnosticId::cmd_err_native_constant_payload_unsupported, Diagnostic::ARG_SYM, pending.ownerName);

        for (const DataSegmentRelocation& relocation : segment.relocations())
        {
            if (relocation.offset < allocation.offset)
                continue;
            if (relocation.offset - allocation.offset >= allocation.size)
                continue;
            if (relocation.kind != DataSegmentRelocationKind::DataSegmentOffset)
                continue;

            SWC_RESULT(enqueueSourceOffset(pending.ownerName, pending.shardIndex, relocation.targetOffset));
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

        SWC_RESULT(enqueuePointer(ownerName, reinterpret_cast<const void*>(relocation.targetAddress)));
    }

    return Result::Continue;
}

Result NativeRDataCollector::enqueuePointer(const Utf8& ownerName, const void* ptr)
{
    if (!ptr)
        return Result::Continue;

    uint32_t  shardIndex = 0;
    const Ref sourceRef  = builder_->compiler().cstMgr().findDataSegmentRef(shardIndex, ptr);
    if (sourceRef == INVALID_REF)
        return builder_->reportError(DiagnosticId::cmd_err_native_constant_storage_unsupported, Diagnostic::ARG_SYM, ownerName);

    return enqueueSourceOffset(ownerName, shardIndex, sourceRef);
}

Result NativeRDataCollector::enqueueSourceOffset(const Utf8& ownerName, const uint32_t shardIndex, const uint32_t sourceOffset)
{
    const DataSegment&    segment = builder_->compiler().cstMgr().shardDataSegment(shardIndex);
    DataSegmentAllocation allocation;
    if (!segment.findAllocation(allocation, sourceOffset))
        return builder_->reportError(DiagnosticId::cmd_err_native_constant_payload_unsupported, Diagnostic::ARG_SYM, ownerName);

    if (!seen_[shardIndex].insert(allocation.offset).second)
        return Result::Continue;

    reachableOffsets_[shardIndex].push_back(allocation.offset);
    owners_[shardIndex].emplace(allocation.offset, ownerName);
    pending_.push_back({
        .shardIndex   = shardIndex,
        .sourceOffset = allocation.offset,
        .ownerName    = ownerName,
    });
    return Result::Continue;
}

Result NativeRDataCollector::emitReachableAllocations()
{
    std::array<std::vector<DataSegmentAllocation>, ConstantManager::SHARD_COUNT> emittedAllocations;

    for (uint32_t shardIndex = 0; shardIndex < ConstantManager::SHARD_COUNT; ++shardIndex)
    {
        auto& reachable = reachableOffsets_[shardIndex];
        std::ranges::sort(reachable);

        const DataSegment& segment  = builder_->compiler().cstMgr().shardDataSegment(shardIndex);
        auto&              mappings = builder_->rdataAllocationMap[shardIndex];
        mappings.clear();
        emittedAllocations[shardIndex].reserve(reachable.size());
        mappings.reserve(reachable.size());

        for (const uint32_t sourceOffset : reachable)
        {
            DataSegmentAllocation allocation;
            if (!segment.findAllocation(allocation, sourceOffset) || allocation.offset != sourceOffset)
            {
                const auto ownerIt   = owners_[shardIndex].find(sourceOffset);
                const Utf8 ownerName = ownerIt != owners_[shardIndex].end() ? ownerIt->second : Utf8("<rdata>");
                return builder_->reportError(DiagnosticId::cmd_err_native_constant_payload_unsupported, Diagnostic::ARG_SYM, ownerName);
            }

            const uint32_t emittedOffset = Math::alignUpU32(static_cast<uint32_t>(builder_->mergedRData.bytes.size()), std::max(allocation.align, 1u));
            if (builder_->mergedRData.bytes.size() < emittedOffset)
                builder_->mergedRData.bytes.resize(emittedOffset, std::byte{0});

            const uint32_t insertOffset = static_cast<uint32_t>(builder_->mergedRData.bytes.size());
            SWC_ASSERT(insertOffset == emittedOffset);
            builder_->mergedRData.bytes.resize(insertOffset + allocation.size);

            const auto* sourceBytes = segment.ptr<std::byte>(allocation.offset);
            SWC_ASSERT(sourceBytes != nullptr);
            std::memcpy(builder_->mergedRData.bytes.data() + insertOffset, sourceBytes, allocation.size);

            emittedAllocations[shardIndex].push_back(allocation);
            mappings.push_back({
                .sourceOffset  = allocation.offset,
                .size          = allocation.size,
                .emittedOffset = emittedOffset,
            });
        }
    }

    for (uint32_t shardIndex = 0; shardIndex < ConstantManager::SHARD_COUNT; ++shardIndex)
    {
        const DataSegment& segment          = builder_->compiler().cstMgr().shardDataSegment(shardIndex);
        const auto&        allocations      = emittedAllocations[shardIndex];
        const auto&        relocations      = segment.relocations();
        const auto&        allocationOwners = owners_[shardIndex];

        for (size_t i = 0; i < allocations.size(); ++i)
        {
            const DataSegmentAllocation&        allocation = allocations[i];
            const NativeRDataAllocationMapEntry mapping    = builder_->rdataAllocationMap[shardIndex][i];

            for (const DataSegmentRelocation& relocation : relocations)
            {
                if (relocation.offset < allocation.offset)
                    continue;
                if (relocation.offset - allocation.offset >= allocation.size)
                    continue;

                NativeSectionRelocation record;
                record.offset = mapping.emittedOffset + (relocation.offset - allocation.offset);

                if (relocation.kind == DataSegmentRelocationKind::DataSegmentOffset)
                {
                    uint32_t targetOffset = 0;
                    if (!builder_->tryMapRDataSourceOffset(targetOffset, shardIndex, relocation.targetOffset))
                    {
                        const auto ownerIt   = allocationOwners.find(allocation.offset);
                        const Utf8 ownerName = ownerIt != allocationOwners.end() ? ownerIt->second : Utf8("<rdata>");
                        return builder_->reportError(DiagnosticId::cmd_err_native_constant_payload_unsupported, Diagnostic::ARG_SYM, ownerName);
                    }

                    record.symbolName = K_R_DATA_BASE_SYMBOL;
                    record.addend     = targetOffset;
                    builder_->mergedRData.relocations.push_back(record);
                    continue;
                }

                SWC_ASSERT(relocation.kind == DataSegmentRelocationKind::FunctionSymbol);
                const SymbolFunction* targetFunction = relocation.targetSymbol;
                SWC_ASSERT(targetFunction != nullptr);
                if (!targetFunction)
                    return builder_->reportError(DiagnosticId::cmd_err_native_invalid_local_function_relocation);

                if (targetFunction->isForeign())
                {
                    record.symbolName = targetFunction->resolveForeignFunctionName(builder_->ctx());
                    record.addend     = 0;
                    builder_->mergedRData.relocations.push_back(record);
                    continue;
                }

                const auto functionIt = builder_->functionBySymbol.find(relocation.targetSymbol);
                if (functionIt == builder_->functionBySymbol.end())
                    return builder_->reportError(DiagnosticId::cmd_err_native_invalid_local_function_relocation);

                record.symbolName = functionIt->second->symbolName;
                record.addend     = 0;
                builder_->mergedRData.relocations.push_back(record);
            }
        }
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
