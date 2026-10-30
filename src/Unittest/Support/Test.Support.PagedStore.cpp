#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Core/DataSegment.h"
#include "Support/Core/PagedStore.h"
#include "Support/Os/Os.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(PagedStore_ReleasedProximityPagesAreDecommitted)
{
    PagedStore survivor(4096);
    survivor.enableProximityPages();
    const Ref live              = survivor.reserveRange(4, 1, true);
    survivor.at<uint32_t>(live) = 42;

    void* released = nullptr;
    {
        PagedStore store(8192);
        store.enableProximityPages();
        const Ref allocation = store.reserveRange(4, 1, true);
        released             = store.ptr<std::byte>(allocation);
        if (!Os::isProximityMemory(released))
            return Result::Error;
    }
    MEMORY_BASIC_INFORMATION memory{};
    if (!VirtualQuery(released, &memory, sizeof(memory)) || memory.State != MEM_RESERVE || survivor.at<uint32_t>(live) != 42)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DataSegment_ReleasedLargeProximityBlocksAreDecommitted)
{
    void* released = nullptr;
    {
        DataSegment segment;
        segment.enableProximityStorage();
        const auto [offset, ptr] = segment.reserveBytes(PagedStore::K_DEFAULT_PAGE_SIZE * 2 + 3, 1, true);
        SWC_UNUSED(offset);
        released = ptr;
        if (!Os::isProximityMemory(released))
            return Result::Error;
    }
    MEMORY_BASIC_INFORMATION memory{};
    if (!VirtualQuery(released, &memory, sizeof(memory)) || memory.State != MEM_RESERVE)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DataSegment_FillPreservesOffsetsAcrossPagesAndLargeBlocks)
{
    for (const bool proximity : {false, true})
    {
        DataSegment segment;
        if (proximity)
            segment.enableProximityStorage();
        segment.fill(std::byte{0xCD});

        constexpr std::array<uint32_t, 4> sizes = {PagedStore::K_DEFAULT_PAGE_SIZE - 5, 17, PagedStore::K_DEFAULT_PAGE_SIZE * 2 + 3, 9};
        std::array<std::pair<uint32_t, std::byte*>, sizes.size()> allocations;
        for (size_t i = 0; i < sizes.size(); ++i)
            allocations[i] = segment.reserveBytes(sizes[i], 64, true);
        const uint32_t extent = segment.extentSize();
        segment.fill(std::byte{0xCD});
        if (segment.extentSize() != extent)
            return Result::Error;

        for (size_t i = 0; i < sizes.size(); ++i)
        {
            const auto [offset, ptr] = allocations[i];
            if (segment.ptr<std::byte>(offset) != ptr || segment.findRef(ptr) != offset)
                return Result::Error;
            if (!std::ranges::all_of(std::span{ptr, sizes[i]}, [](std::byte value) { return value == std::byte{0xCD}; }))
                return Result::Error;
        }
        const auto [offset, ptr] = segment.reserveBytes(4, 1, true);
        SWC_UNUSED(offset);
        if (*ptr != std::byte{0})
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(PagedStore_MoveConstructionPreservesProximityAllocation)
{
    PagedStore source(32);
    source.enableProximityPages();
    const Ref first            = source.reserveRange(32, 1, true);
    source.at<uint32_t>(first) = 42;

    PagedStore moved(std::move(source));
    const Ref  next = moved.reserveRange(32, 1, true);
    if (moved.at<uint32_t>(first) != 42 || !Os::isProximityMemory(moved.ptr<std::byte>(next)))
        return Result::Error;

    const Ref reused = source.reserveRange(32, 1, true);
    if (!Os::isProximityMemory(source.ptr<std::byte>(reused)))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PagedStore_MoveAssignmentPreservesAllocationPolicies)
{
    PagedStore source(32);
    source.enableProximityPages();
    const Ref first            = source.reserveRange(32, 1, true);
    source.at<uint32_t>(first) = 42;
    PagedStore target(32);
    const Ref  previous           = target.reserveRange(32, 1, true);
    target.at<uint32_t>(previous) = 7;

    target         = std::move(source);
    const Ref next = target.reserveRange(32, 1, true);
    if (target.at<uint32_t>(first) != 42 || !Os::isProximityMemory(target.ptr<std::byte>(next)))
        return Result::Error;

    const Ref reused = source.reserveRange(32, 1, true);
    if (source.at<uint32_t>(previous) != 7 || Os::isProximityMemory(source.ptr<std::byte>(reused)))
        return Result::Error;
}
SWC_TEST_END()

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

SWC_TEST_BEGIN(DataSegment_CopyDataSegmentRelocationTargetsPreservesOrder)
{
    DataSegment segment;
    segment.addRelocation(0, DataSegmentRef{.shardIndex = 2, .offset = 10});
    segment.addFunctionRelocation(8, nullptr);
    segment.addRelocation(16, DataSegmentRef{.shardIndex = INVALID_REF, .offset = 20});
    segment.addRelocation(24, DataSegmentRef{.shardIndex = 3, .offset = 30});

    const auto targets = segment.copyDataSegmentRelocationTargets();
    if (targets.size() != 2 || targets[0].shardIndex != 2 || targets[0].offset != 10 || targets[1].shardIndex != 3 || targets[1].offset != 30)
        return Result::Error;
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

SWC_TEST_BEGIN(DataSegment_RelocationRangeMergePreservesEqualOffsetOrder)
{
    DataSegment segment;
    segment.addRelocation(64, 1);
    segment.addRelocation(64, 2);
    segment.addRelocation(32, 3);
    segment.addRelocation(64, 4);

    std::vector<DataSegmentRelocation> relocations;
    segment.copyRelocations(relocations, 0, 128);
    constexpr std::array expectedTargets{3u, 1u, 2u, 4u};
    if (relocations.size() != expectedTargets.size())
        return Result::Error;
    for (size_t i = 0; i < relocations.size(); ++i)
    {
        if (relocations[i].targetOffset != expectedTargets[i])
            return Result::Error;
    }
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
    prefix[0]                         = std::byte{0x71};
    prefix[31]                        = std::byte{0x72};

    struct Allocation
    {
        uint32_t   offset;
        uint32_t   size;
        std::byte* bytes;
    };
    std::vector<Allocation> allocations;
    for (uint32_t i = 0; i < 128; ++i)
    {
        const uint32_t size        = i ? 17 + i % 23 : PagedStore::K_DEFAULT_PAGE_SIZE + 1;
        const auto [offset, bytes] = segment.reserveBytes(size, 64, false);
        bytes[0]                   = std::byte{0x31};
        bytes[size - 1]            = std::byte{0x32};
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

SWC_TEST_BEGIN(PagedStore_ChunkIterationPreservesAlignedValuesAcrossPages)
{
    struct alignas(alignof(std::max_align_t)) Value
    {
        uint64_t first;
        uint64_t second;

        bool operator==(const Value&) const = default;
    };
    std::array<Value, 17> values;
    for (size_t i = 0; i < values.size(); ++i)
        values[i] = {i * 31 + 7, i * 43 + 11};

    for (const uint32_t prefix : {0u, 1u, 7u, 16u, 33u, 60u})
    {
        for (const size_t count : {0u, 1u, 3u, 4u, 5u, 17u})
        {
            PagedStore store(64);
            if (prefix)
                store.reserveRange(prefix, 1, false);
            const SpanRef ref  = store.pushSpan(std::span<const Value>(values).first(count));
            const auto    view = store.span<Value>(ref.get());
            if (view.size() != count)
                return Result::Error;

            size_t next = 0;
            for (auto it = view.chunksBegin(); it != view.chunksEnd(); ++it)
            {
                if (!it->count || it->count > count - next || reinterpret_cast<uintptr_t>(it->ptr) % alignof(Value))
                    return Result::Error;
                const std::span chunk(static_cast<const Value*>(it->ptr), it->count);
                if (!std::ranges::equal(chunk, std::span<const Value>(values).subspan(next, chunk.size())))
                    return Result::Error;
                next += chunk.size();
            }
            if (next != count)
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PagedStore_ChunkSentinelCompletesEmptyAndMultiPageSpans)
{
    const auto end     = PagedStore::SpanView{}.chunksEnd();
    const auto invalid = PagedStore::SpanView{}.chunksBegin();
    if (invalid != end || !(end == invalid))
        return Result::Error;

    std::array<uint32_t, 97> values;
    std::iota(values.begin(), values.end(), 1u);
    for (const size_t count : {size_t{0}, size_t{1}, values.size()})
    {
        PagedStore    store(64);
        const SpanRef ref   = store.pushSpan(std::span<const uint32_t>(values).first(count));
        const auto    view  = store.span<uint32_t>(ref.get());
        auto          it    = view.chunksBegin();
        const bool    empty = count == 0;
        if ((it == end) != empty || (end == it) != empty || (it != end) == empty || (end != it) == empty)
            return Result::Error;

        size_t seen = 0;
        for (; it != end; ++it)
        {
            if (!it->count || it->count > count - seen)
                return Result::Error;
            for (const uint32_t value : std::span(static_cast<const uint32_t*>(it->ptr), it->count))
            {
                if (value != values[seen++])
                    return Result::Error;
            }
        }
        if (seen != count || !(it == end))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(PagedStore_RawSpanAlignmentPreservesPayloadAndZeroConvention)
{
    std::array<uint8_t, 37> bytes;
    for (size_t i = 0; i < bytes.size(); ++i)
        bytes[i] = static_cast<uint8_t>(i * 17 + 3);

    for (const bool contiguous : {false, true})
        for (const uint32_t alignment : {0u, 1u, 2u, 4u, 8u})
        {
            for (const uint32_t prefix : {0u, 1u, 7u, 15u, 28u})
            {
                PagedStore store(32);
                if (prefix)
                    store.reserveRange(prefix, 1, false);
                const uint32_t count              = contiguous ? 9 : static_cast<uint32_t>(bytes.size());
                const SpanRef  ref                = contiguous ? store.pushSpanContiguousRaw(bytes.data(), 1, alignment, count) : store.pushSpanRaw(bytes.data(), 1, alignment, count);
                const uint32_t effectiveAlignment = alignment ? alignment : 1;
                const auto     view               = store.spanView(ref.get(), 1, effectiveAlignment);
                if (view.size() != count)
                    return Result::Error;

                size_t next = 0;
                for (auto it = view.chunksBegin(); it != view.chunksEnd(); ++it)
                {
                    if (!it->count || it->count > count - next || reinterpret_cast<uintptr_t>(it->ptr) % effectiveAlignment)
                        return Result::Error;
                    const std::span chunk(static_cast<const uint8_t*>(it->ptr), it->count);
                    if (!std::ranges::equal(chunk, std::span<const uint8_t>(bytes).subspan(next, chunk.size())))
                        return Result::Error;
                    next += chunk.size();
                }
                if (next != count)
                    return Result::Error;
            }
        }
    return Result::Continue;
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

SWC_TEST_BEGIN(PagedStore_ReadersKeepReferencesAcrossPageGrowth)
{
    constexpr uint32_t                 pageCount = 256;
    PagedStore                         store(64);
    std::array<Ref, pageCount>         refs{};
    std::array<const void*, pageCount> addresses{};
    std::atomic<uint32_t>              published{0};
    std::atomic<bool>                  done{false};
    std::atomic<bool>                  failed{false};
    std::latch                         ready(2);

    auto readPages = [&] {
        ready.count_down();
        do
        {
            const uint32_t count = published.load(std::memory_order_acquire);
            if (!count)
            {
                std::this_thread::yield();
                continue;
            }
            for (const uint32_t index : {0u, count / 2, count - 1})
            {
                const Ref ref = refs[index];
                if (!store.containsRef(ref, 64) || store.ptr<uint32_t>(ref) != addresses[index] ||
                    store.at<uint32_t>(ref) != index || store.at<uint32_t>(ref + 60) != ~index ||
                    store.findRef(addresses[index]) != ref)
                {
                    failed.store(true, std::memory_order_relaxed);
                    return;
                }
            }
        } while (!done.load(std::memory_order_acquire));
    };

    std::jthread first(readPages);
    std::jthread second(readPages);
    ready.wait();
    for (uint32_t index = 0; index < pageCount; ++index)
    {
        const auto [bytes, ref]      = store.reserveSpan(64);
        store.at<uint32_t>(ref)      = index;
        store.at<uint32_t>(ref + 60) = ~index;
        refs[index]                  = ref;
        addresses[index]             = bytes.data();
        published.store(index + 1, std::memory_order_release);
    }
    done.store(true, std::memory_order_release);
    first.join();
    second.join();
    if (failed.load(std::memory_order_relaxed))
        return Result::Error;

    PagedStore moved(std::move(store));
    for (uint32_t index = 0; index < pageCount; ++index)
    {
        if (moved.ptr<uint32_t>(refs[index]) != addresses[index] || moved.at<uint32_t>(refs[index]) != index)
            return Result::Error;
    }
    const Ref reused = store.pushBack(uint32_t{42});
    if (store.at<uint32_t>(reused) != 42)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PagedStore_ReferencesSurviveGrowthAndMovesWithoutReverseLookup)
{
    PagedStore                source(64, PagedStore::ReverseLookup::Disabled);
    std::array<Ref, 65>       refs;
    std::array<uint32_t*, 65> addresses;
    for (uint32_t index = 0; index < refs.size(); ++index)
    {
        refs[index]       = source.reserveRange(64, 1, true);
        addresses[index]  = source.ptr<uint32_t>(refs[index]);
        *addresses[index] = index + 1;
    }

    PagedStore moved(std::move(source));
    PagedStore target(32);
    const Ref  oldRef = target.pushBack(uint32_t{99});
    target            = std::move(moved);
    for (uint32_t index = 0; index < refs.size(); ++index)
    {
        if (!target.containsRef(refs[index], 64) || target.ptr<uint32_t>(refs[index]) != addresses[index] || *addresses[index] != index + 1)
            return Result::Error;
    }

    // Move assignment swaps ownership, including the enabled index of the old target.
    if (moved.findRef(moved.ptr<uint32_t>(oldRef)) != oldRef || moved.at<uint32_t>(oldRef) != 99)
        return Result::Error;
    const Ref indexed = moved.reserveRange(32, 1, true);
    if (moved.findRef(moved.ptr<uint32_t>(indexed)) != indexed)
        return Result::Error;

    const Ref reused = source.pushBack(uint32_t{42});
    if (source.at<uint32_t>(reused) != 42)
        return Result::Error;
    target.clear();
    const Ref afterClear = target.pushBack(uint32_t{17});
    if (target.at<uint32_t>(afterClear) != 17)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PagedStore_FindRefRejectsAddressesOutsideLiveBytes)
{
    PagedStore store(64);
    if (store.findRef(nullptr) != INVALID_REF)
        return Result::Error;

    const auto [bytes, ref] = store.reserveSpan(8);
    const uintptr_t begin   = reinterpret_cast<uintptr_t>(bytes.data());
    if (store.findRef(bytes.data()) != ref || store.findRef(bytes.data() + 7) != ref + 7)
        return Result::Error;
    for (const uintptr_t address : {begin - 1, begin + 8, begin + 63, begin + 64})
    {
        if (store.findRef(reinterpret_cast<const void*>(address)) != INVALID_REF)
            return Result::Error;
    }

    if constexpr (sizeof(uintptr_t) > sizeof(uint32_t))
    {
        const uintptr_t farAddress = begin + (uint64_t{1} << 32);
        if (store.findRef(reinterpret_cast<const void*>(farAddress)) != INVALID_REF)
            return Result::Error;
    }

    store.clear();
    if (store.findRef(bytes.data()) != INVALID_REF)
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
        std::array input       = {'x', 'A', '\0', 'B', 'z'};
        const auto [view, ref] = segment.addString(std::string_view(input.data() + 1, 3));
        stored                 = view;
        storedRef              = ref;
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

    const uint32_t extent    = segment.extentSize();
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
    const auto [stored, storedRef]     = segment.addString(value);
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
    const uint32_t extent    = segment.extentSize();
    const auto [hit, hitRef] = segment.addString(value);
    // Restoring mutable payload bytes does not rewrite the pool's owned lookup key.
    if (hitRef != storedRef || hit.data() != stored.data() || hit.front() != 'X' || segment.extentSize() != extent)
        return Result::Error;
    if (slots[1] != hit.data() || segment.copyRelocations().size() != 1)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DataSegment_OffsetCopiesPreservePayloadGapsAndTrailingZeros)
{
    struct Payload
    {
        uint32_t  offset;
        uint32_t  count;
        std::byte value;
    };
    for (const bool pagedPrefix : {false, true})
    {
        for (const bool largeBlocks : {false, true})
        {
            DataSegment             segment;
            SmallVector<Payload, 4> payloads;
            if (pagedPrefix)
            {
                const uint32_t count            = PagedStore::K_DEFAULT_PAGE_SIZE - 7;
                const auto [firstOffset, first] = segment.reserveBytes(count, 8, false);
                std::fill_n(first, count, std::byte{0x31});
                payloads.push_back({firstOffset, count, std::byte{0x31}});
                const auto [secondOffset, second] = segment.reserveBytes(13, 8, false);
                std::fill_n(second, 13, std::byte{0x42});
                payloads.push_back({secondOffset, 13, std::byte{0x42}});
            }
            if (largeBlocks)
            {
                const uint32_t count            = PagedStore::K_DEFAULT_PAGE_SIZE + 17;
                const auto [largeOffset, large] = segment.reserveBytes(count, 64, false);
                std::fill_n(large, count, std::byte{0x53});
                payloads.push_back({largeOffset, count, std::byte{0x53}});
                const auto [lastOffset, last] = segment.reserveBytes(17, 64, false);
                std::fill_n(last, 17, std::byte{0x64});
                payloads.push_back({lastOffset, 17, std::byte{0x64}});
            }
            std::vector<std::byte> expected(segment.extentSize() + 11, std::byte{0});
            for (const Payload& payload : payloads)
                std::fill_n(expected.data() + payload.offset, payload.count, payload.value);
            std::vector<std::byte> actual(expected.size(), std::byte{0xCC});
            segment.copyToPreserveOffsets(actual);
            if (actual != expected)
                return Result::Error;
            if (largeBlocks)
            {
                std::ranges::fill(actual, std::byte{0xCC});
                segment.copyTo(actual);
                if (actual != expected)
                    return Result::Error;
            }
        }
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
