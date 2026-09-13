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

    const auto [firstSpan, firstRef]   = store.pushCopySpan(std::span{first.data(), first.size()});
    const auto [secondSpan, secondRef] = store.pushCopySpan(std::span{second.data(), second.size()});
    SWC_UNUSED(firstSpan);
    SWC_UNUSED(secondSpan);

    if (firstRef != 0 || secondRef != 32)
        return Result::Error;
    if (store.size() != 40 || store.extentSize() != 48)
        return Result::Error;

    std::array<std::byte, 48> out;
    out.fill(std::byte{0xCC});
    store.copyToPreserveOffsets(std::span{out.data(), out.size()});

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

SWC_TEST_BEGIN(DataSegment_RelocationRangesPreserveIndexedAndTailEntries)
{
    DataSegment segment;
    for (uint32_t i = 0; i < 128; ++i)
        segment.addRelocation(i * 16, i);

    std::vector<DataSegmentRelocation> relocations;
    segment.copyRelocations(relocations, 32, 64);
    if (relocations.size() != 4)
        return Result::Error;
    for (uint32_t i = 0; i < relocations.size(); ++i)
    {
        if (relocations[i].offset != (i + 2) * 16 || relocations[i].targetOffset != i + 2)
            return Result::Error;
    }

    // An unsorted tail outside the query must not disturb the indexed range.
    segment.addRelocation(8, 500);
    segment.copyRelocations(relocations, 32, 64);
    if (relocations.size() != 4 || relocations.front().offset != 32 || relocations.back().offset != 80)
        return Result::Error;

    segment.addRelocation(56, 501);
    segment.copyRelocations(relocations, 32, 64);
    constexpr std::array expectedOffsets{32u, 48u, 56u, 64u, 80u};
    if (relocations.size() != expectedOffsets.size())
        return Result::Error;
    for (size_t i = 0; i < relocations.size(); ++i)
        if (relocations[i].offset != expectedOffsets[i])
            return Result::Error;
    if (relocations[2].targetOffset != 501)
        return Result::Error;

    DataSegment repeated;
    for (uint32_t i = 0; i < 64; ++i)
        repeated.addRelocation(16, i);
    auto expected = repeated.copyRelocations();
    std::ranges::sort(expected, {}, &DataSegmentRelocation::offset);
    repeated.copyRelocations(relocations, 16, 1);
    if (relocations.size() != expected.size())
        return Result::Error;
    for (size_t i = 0; i < relocations.size(); ++i)
        if (relocations[i].targetOffset != expected[i].targetOffset)
            return Result::Error;

    segment.copyRelocations(relocations, 32, 0);
    if (!relocations.empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DataSegment_FindAllocationUsesPublishedAllocations)
{
    DataSegment segment;
    std::array  bytes{std::byte{1}, std::byte{2}, std::byte{3}};

    const auto [span, offset] = segment.addSpan(std::span{bytes.data(), bytes.size()});
    SWC_UNUSED(span);

    DataSegmentAllocation allocation;
    if (!segment.findAllocation(allocation, offset + 1))
        return Result::Error;
    if (allocation.offset != offset || allocation.size != static_cast<uint32_t>(bytes.size()))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DataSegment_LargeBlockPointersPreservePagedPrefixAndAlignedAllocations)
{
    DataSegment segment;
    const auto [prefixOffset, prefix] = segment.reserveBytes(32, 8, false);
    prefix[0] = std::byte{0x71};
    prefix[31] = std::byte{0x72};

    struct Allocation
    {
        uint32_t   offset;
        uint32_t   size;
        std::byte* bytes;
    };
    std::vector<Allocation> allocations;
    for (uint32_t i = 0; i < 128; ++i)
    {
        const uint32_t size = i ? 17 + i % 23 : PagedStore::K_DEFAULT_PAGE_SIZE + 1;
        const auto [offset, bytes] = segment.reserveBytes(size, 64, false);
        bytes[0] = std::byte{0x31};
        bytes[size - 1] = std::byte{0x32};
        allocations.push_back({offset, size, bytes});
    }

    const DataSegment& constSegment = segment;
    if (segment.ptr<std::byte>(prefixOffset) != prefix || constSegment.ptr<std::byte>(prefixOffset + 31) != prefix + 31)
        return Result::Error;
    if (prefix[0] != std::byte{0x71} || prefix[31] != std::byte{0x72})
        return Result::Error;

    for (const Allocation& allocation : allocations)
    {
        if (segment.ptr<std::byte>(allocation.offset) != allocation.bytes)
            return Result::Error;
        if (constSegment.ptr<std::byte>(allocation.offset + allocation.size - 1) != allocation.bytes + allocation.size - 1)
            return Result::Error;
        if (segment.findRef(allocation.bytes + allocation.size / 2) != allocation.offset + allocation.size / 2)
            return Result::Error;
        if (allocation.bytes[0] != std::byte{0x31} || allocation.bytes[allocation.size - 1] != std::byte{0x32})
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(PagedStore_ReserveSpanReturnsWritableContiguousStorage)
{
    PagedStore store(32);

    const auto [firstSpan, firstRef] = store.reserveSpan(24);
    firstSpan.front()                = std::byte{0x11};
    firstSpan.back()                 = std::byte{0x22};

    const auto [secondSpan, secondRef] = store.reserveSpan(16, 8);
    secondSpan.front()                 = std::byte{0x33};
    secondSpan.back()                  = std::byte{0x44};

    if (firstRef != 0 || secondRef != 32)
        return Result::Error;
    if (firstSpan.size() != 24 || secondSpan.size() != 16)
        return Result::Error;
    if (store.ptr<std::byte>(firstRef) != firstSpan.data() || store.ptr<std::byte>(secondRef) != secondSpan.data())
        return Result::Error;
    if (store.at<std::byte>(firstRef) != std::byte{0x11} || store.at<std::byte>(firstRef + 23) != std::byte{0x22})
        return Result::Error;
    if (store.at<std::byte>(secondRef) != std::byte{0x33} || store.at<std::byte>(secondRef + 15) != std::byte{0x44})
        return Result::Error;

    return Result::Continue;
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

    const auto [storedSpan, storedRef] = store.pushCopySpan(std::span{payload.data(), payload.size()});
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
    const auto [prefixSpan, prefixRef] = store.pushCopySpan(std::span{prefix.data(), prefix.size()});
    SWC_UNUSED(prefixSpan);

    const Ref largeRef = store.reserveRange(80, 8, true);

    if (prefixRef != 0 || largeRef != 8)
        return Result::Error;
    if (store.size() != 88 || store.extentSize() != 88)
        return Result::Error;

    std::array<std::byte, 88> out;
    out.fill(std::byte{0xCC});
    store.copyToPreserveOffsets(std::span{out.data(), out.size()});

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

SWC_TEST_BEGIN(DataSegment_StringPoolOwnsInputsAndPreservesViewsAcrossGrowth)
{
    DataSegment      segment;
    std::string_view stored;
    Ref              storedRef = INVALID_REF;
    {
        std::array input      = {'x', 'A', '\0', 'B', 'z'};
        const auto [view, ref] = segment.addString(std::string_view(input.data() + 1, 3));
        stored                = view;
        storedRef             = ref;
        if (stored.data() == input.data() + 1)
            return Result::Error;
        input.fill('!');
    }
    const std::string_view expected{"A\0B", 3};
    if (stored != expected || stored.data()[stored.size()] != '\0')
        return Result::Error;

    const auto [empty, emptyRef] = segment.addString(std::string_view{});
    if (emptyRef == INVALID_REF || !empty.empty() || !empty.data() || empty.data()[0] != '\0')
        return Result::Error;
    if (segment.addString(Utf8{}).second != emptyRef)
        return Result::Error;

    const auto [subview, subviewRef] = segment.addString(stored.substr(1));
    if (subview != expected.substr(1) || subview.data() == stored.data() + 1 || subviewRef == storedRef)
        return Result::Error;
    if (subview.data()[subview.size()] != '\0')
        return Result::Error;

    for (uint32_t index = 0; index < 192; ++index)
    {
        std::string text = std::format("string-pool-growth-{}-", index);
        text.append(128, 'g');
        const auto [view, ref] = segment.addString(text);
        if (view != text || view.data()[view.size()] != '\0' || ref == INVALID_REF)
            return Result::Error;
    }
    const std::string large(PagedStore::K_DEFAULT_PAGE_SIZE + 17, 'L');
    const auto [largeView, largeRef] = segment.addString(large);
    if (largeView != large || largeView.data()[largeView.size()] != '\0' || largeRef == INVALID_REF)
        return Result::Error;

    const uint32_t extent   = segment.extentSize();
    const auto [hit, hitRef] = segment.addString(expected);
    if (hitRef != storedRef || hit.data() != stored.data() || hit != expected || segment.extentSize() != extent)
        return Result::Error;
    if (segment.addString(stored).second != storedRef || segment.addString(subview).second != subviewRef)
        return Result::Error;
    if (segment.addString(large).second != largeRef || segment.addString("").second != emptyRef)
        return Result::Error;
    if (segment.extentSize() != extent)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DataSegment_StringPoolRelocationsRetainIndependentKeysAcrossRestore)
{
    DataSegment segment;
    const auto [baseOffset, slots] = segment.reserveSpan<const char*>(2);
    const std::string_view value{"field\0value", 11};
    constexpr uint32_t     fieldOffset = sizeof(const char*);
    const uint32_t         length      = segment.addString(baseOffset, fieldOffset, value);
    const auto [stored, storedRef] = segment.addString(value);
    if (length != value.size() || slots[0] != nullptr || slots[1] != stored.data() || stored != value)
        return Result::Error;
    if (stored.data()[stored.size()] != '\0')
        return Result::Error;
    DataSegmentRelocation relocation;
    if (!segment.findRelocation(relocation, baseOffset + fieldOffset, DataSegmentRelocationKind::DataSegmentOffset))
        return Result::Error;
    if (relocation.targetOffset != storedRef || relocation.targetShardIndex != INVALID_REF)
        return Result::Error;

    std::vector<std::byte> snapshot(segment.extentSize());
    segment.copyToPreserveOffsets(snapshot);
    snapshot[storedRef] = std::byte{0x58};
    segment.restoreFromPreserveOffsets(snapshot);
    const uint32_t extent   = segment.extentSize();
    const auto [hit, hitRef] = segment.addString(value);
    // Restoring mutable payload bytes does not rewrite the pool's owned lookup key.
    if (hitRef != storedRef || hit.data() != stored.data() || hit.front() != 'X' || segment.extentSize() != extent)
        return Result::Error;
    if (slots[1] != hit.data() || segment.copyRelocations().size() != 1)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
