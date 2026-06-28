#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Core/DataSegment.h"
#include "Support/Core/PagedStore.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(PagedStore_CopyToPreserveOffsetsKeepsSparseLayout)
{
    PagedStore store(32);

    std::array<std::byte, 24> first;
    std::array<std::byte, 16> second;
    first.fill(std::byte{0x11});
    second.fill(std::byte{0x22});

    const auto [firstSpan, firstRef]   = store.pushCopySpan(std::span<const std::byte>{first.data(), first.size()});
    const auto [secondSpan, secondRef] = store.pushCopySpan(std::span<const std::byte>{second.data(), second.size()});
    SWC_UNUSED(firstSpan);
    SWC_UNUSED(secondSpan);

    if (firstRef != 0 || secondRef != 32)
        return Result::Error;
    if (store.size() != 40 || store.extentSize() != 48)
        return Result::Error;

    std::array<std::byte, 48> out;
    out.fill(std::byte{0xCC});
    store.copyToPreserveOffsets(std::span<std::byte>{out.data(), out.size()});

    for (size_t i = 0; i < first.size(); ++i)
    {
        if (out[i] != first[i])
            return Result::Error;
    }

    for (size_t i = first.size(); i < secondRef; ++i)
    {
        if (out[i] != std::byte{0})
            return Result::Error;
    }

    for (size_t i = 0; i < second.size(); ++i)
    {
        if (out[secondRef + i] != second[i])
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(DataSegment_RelocationIndexHandlesInterleavedMonotonicAdds)
{
    DataSegment segment;

    const uint32_t targetOffset = segment.reserveBlock(1, 1, true);
    const uint32_t firstOffset  = segment.reserveBlock(sizeof(void*), alignof(void*), true);
    segment.addRelocation(firstOffset, targetOffset);

    std::vector<DataSegmentRelocation> relocations;
    segment.copyRelocations(relocations, firstOffset, sizeof(void*));
    if (relocations.size() != 1 || relocations[0].offset != firstOffset)
        return Result::Error;

    const uint32_t secondOffset = segment.reserveBlock(sizeof(void*), alignof(void*), true);
    segment.addRelocation(secondOffset, targetOffset);

    segment.copyRelocations(relocations, firstOffset, secondOffset - firstOffset + static_cast<uint32_t>(sizeof(void*)));
    if (relocations.size() != 2)
        return Result::Error;
    if (relocations[0].offset != firstOffset || relocations[1].offset != secondOffset)
        return Result::Error;

    DataSegmentRelocation relocation;
    if (!segment.findRelocation(relocation, secondOffset, DataSegmentRelocationKind::DataSegmentOffset))
        return Result::Error;
    if (relocation.targetOffset != targetOffset)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DataSegment_RelocationIndexRebuildsAfterOutOfOrderAdd)
{
    DataSegment segment;

    const uint32_t targetOffset = segment.reserveBlock(1, 1, true);
    segment.addRelocation(64, targetOffset);

    std::vector<DataSegmentRelocation> relocations;
    segment.copyRelocations(relocations, 0, 128);
    if (relocations.size() != 1 || relocations[0].offset != 64)
        return Result::Error;

    segment.addRelocation(8, targetOffset);
    segment.copyRelocations(relocations, 0, 128);
    if (relocations.size() != 2)
        return Result::Error;
    if (relocations[0].offset != 8 || relocations[1].offset != 64)
        return Result::Error;

    DataSegmentRelocation relocation;
    if (!segment.findRelocation(relocation, 8, DataSegmentRelocationKind::DataSegmentOffset))
        return Result::Error;
    if (relocation.targetOffset != targetOffset)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DataSegment_FindAllocationUsesPublishedAllocations)
{
    DataSegment segment;
    std::array  bytes{std::byte{1}, std::byte{2}, std::byte{3}};

    const auto [span, offset] = segment.addSpan(std::span<const std::byte>{bytes.data(), bytes.size()});
    SWC_UNUSED(span);

    DataSegmentAllocation allocation;
    if (!segment.findAllocation(allocation, offset + 1))
        return Result::Error;
    if (allocation.offset != offset || allocation.size != static_cast<uint32_t>(bytes.size()))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PagedStore_EmptyCopySpanDoesNotAllocateStorage)
{
    PagedStore store(32);

    const auto [emptySpan, emptyRef] = store.pushCopySpan(std::span<const std::byte>{});
    if (emptyRef != INVALID_REF)
        return Result::Error;
    if (emptySpan.data() != nullptr || !emptySpan.empty())
        return Result::Error;
    if (store.size() != 0 || store.extentSize() != 0)
        return Result::Error;

    std::array<std::byte, 8> payload;
    payload.fill(std::byte{0x5A});

    const auto [storedSpan, storedRef] = store.pushCopySpan(std::span<const std::byte>{payload.data(), payload.size()});
    if (storedRef != 0)
        return Result::Error;
    if (store.findRef(storedSpan.data() + storedSpan.size()) != INVALID_REF)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PagedStore_ReserveRangeSupportsOversizedZeroedBlocks)
{
    PagedStore store(32);

    std::array<std::byte, 3> prefix;
    prefix.fill(std::byte{0x11});
    const auto [prefixSpan, prefixRef] = store.pushCopySpan(std::span<const std::byte>{prefix.data(), prefix.size()});
    SWC_UNUSED(prefixSpan);

    const Ref largeRef = store.reserveRange(80, 8, true);

    if (prefixRef != 0 || largeRef != 8)
        return Result::Error;
    if (store.size() != 88 || store.extentSize() != 88)
        return Result::Error;

    std::array<std::byte, 88> out;
    out.fill(std::byte{0xCC});
    store.copyToPreserveOffsets(std::span<std::byte>{out.data(), out.size()});

    for (size_t i = 0; i < prefix.size(); ++i)
    {
        if (out[i] != prefix[i])
            return Result::Error;
    }

    for (size_t i = prefix.size(); i < out.size(); ++i)
    {
        if (out[i] != std::byte{0})
            return Result::Error;
    }

    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
