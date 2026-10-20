#include "pch.h"
#include "Backend/Native/NativeGlobalLayout.h"
#include "Backend/Micro/MicroRelocation.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Main/CompilerInstance.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isGlobalStorageKind(const DataSegmentKind kind)
    {
        return kind == DataSegmentKind::GlobalZero || kind == DataSegmentKind::GlobalInit;
    }

    const DataSegment& sourceSegment(const NativeBackendBuilder& builder, const DataSegmentKind kind)
    {
        return kind == DataSegmentKind::GlobalInit ? builder.compiler().globalInitSegment() : builder.compiler().globalZeroSegment();
    }
}

void NativeGlobalLayout::build(const NativeBackendBuilder& builder)
{
    zero_ = {};
    init_ = {};

    if (builder.startup)
        reachCode(builder, builder.startup->code.codeRelocations);
    for (const NativeFunctionInfo& info : builder.functionInfos)
    {
        if (info.machineCode)
            reachCode(builder, info.machineCode->codeRelocations);
    }

    for (const SymbolVariable* symbol : builder.regularGlobals)
    {
        if (symbol && symbol->hasGlobalStorage() && isGlobalStorageKind(symbol->globalStorageKind()))
            reach(builder, symbol->globalStorageKind(), symbol->offset());
    }

    // Pointers stored in initialized storage reach further initialized storage. The work list
    // grows while it is walked, so it is indexed rather than iterated.
    const DataSegment&                 initSegment = builder.compiler().globalInitSegment();
    std::vector<DataSegmentRelocation> relocations;
    for (size_t i = 0; i < init_.order.size(); ++i)
    {
        const Allocation allocation = init_.order[i];
        initSegment.copyRelocations(relocations, allocation.sourceOffset, allocation.size);
        for (const DataSegmentRelocation& relocation : relocations)
        {
            if (relocation.kind == DataSegmentRelocationKind::DataSegmentOffset && relocation.targetShardIndex == INVALID_REF)
                reach(builder, DataSegmentKind::GlobalInit, relocation.targetOffset);
        }
    }

    place(zero_);
    place(init_);
}

uint32_t NativeGlobalLayout::map(const DataSegmentKind kind, const uint32_t sourceOffset) const noexcept
{
    const std::vector<Allocation>& bySource = segment(kind).bySource;

    const auto it = std::ranges::upper_bound(bySource, sourceOffset, {}, &Allocation::sourceOffset);
    SWC_ASSERT(it != bySource.begin());
    const Allocation& allocation = *std::prev(it);
    SWC_ASSERT(sourceOffset - allocation.sourceOffset < allocation.size);
    return allocation.emittedOffset + (sourceOffset - allocation.sourceOffset);
}

const NativeGlobalLayout::Segment& NativeGlobalLayout::segment(const DataSegmentKind kind) const noexcept
{
    SWC_ASSERT(isGlobalStorageKind(kind));
    return kind == DataSegmentKind::GlobalInit ? init_ : zero_;
}

void NativeGlobalLayout::reach(const NativeBackendBuilder& builder, const DataSegmentKind kind, const uint32_t sourceOffset)
{
    // Every reservation in a global segment records its allocation, so a reachable offset
    // always falls inside one.
    DataSegmentAllocation allocation;
    const bool            found = sourceSegment(builder, kind).findAllocation(allocation, sourceOffset);
    SWC_ASSERT(found);
    if (!found)
        return;

    Segment& target = kind == DataSegmentKind::GlobalInit ? init_ : zero_;
    if (target.reached.insert(allocation.offset).second)
        target.order.push_back({.sourceOffset = allocation.offset, .size = allocation.size, .align = std::max(allocation.align, 1u)});
}

void NativeGlobalLayout::reachCode(const NativeBackendBuilder& builder, const std::span<const MicroRelocation> relocations)
{
    for (const MicroRelocation& relocation : relocations)
    {
        if (relocation.kind == MicroRelocation::Kind::GlobalZeroAddress)
            reach(builder, DataSegmentKind::GlobalZero, static_cast<uint32_t>(relocation.targetAddress));
        else if (relocation.kind == MicroRelocation::Kind::GlobalInitAddress)
            reach(builder, DataSegmentKind::GlobalInit, static_cast<uint32_t>(relocation.targetAddress));
    }
}

void NativeGlobalLayout::place(Segment& segment)
{
    uint32_t cursor = 0;
    for (Allocation& allocation : segment.order)
    {
        allocation.emittedOffset = Math::alignUpU32(cursor, allocation.align);
        cursor                   = allocation.emittedOffset + allocation.size;
    }

    segment.size     = cursor;
    segment.bySource = segment.order;
    std::ranges::sort(segment.bySource, {}, &Allocation::sourceOffset);
    segment.reached.clear();
}

SWC_END_NAMESPACE();
