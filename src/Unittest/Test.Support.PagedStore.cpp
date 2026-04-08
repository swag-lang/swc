#include "pch.h"

#if SWC_HAS_UNITTEST

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

    const auto [firstSpan, firstRef]   = store.pushCopySpan(ByteSpan{first.data(), first.size()});
    const auto [secondSpan, secondRef] = store.pushCopySpan(ByteSpan{second.data(), second.size()});
    SWC_UNUSED(firstSpan);
    SWC_UNUSED(secondSpan);

    if (firstRef != 0 || secondRef != 32)
        return Result::Error;
    if (store.size() != 40 || store.extentSize() != 48)
        return Result::Error;

    std::array<std::byte, 48> out;
    out.fill(std::byte{0xCC});
    store.copyToPreserveOffsets(ByteSpanRW{out.data(), out.size()});

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

SWC_TEST_BEGIN(PagedStore_EmptyCopySpanDoesNotAllocateStorage)
{
    PagedStore store(32);

    const auto [emptySpan, emptyRef] = store.pushCopySpan(ByteSpan{});
    if (emptyRef != INVALID_REF)
        return Result::Error;
    if (emptySpan.data() != nullptr || !emptySpan.empty())
        return Result::Error;
    if (store.size() != 0 || store.extentSize() != 0)
        return Result::Error;

    std::array<std::byte, 8> payload;
    payload.fill(std::byte{0x5A});

    const auto [storedSpan, storedRef] = store.pushCopySpan(ByteSpan{payload.data(), payload.size()});
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
    const auto [prefixSpan, prefixRef] = store.pushCopySpan(ByteSpan{prefix.data(), prefix.size()});
    SWC_UNUSED(prefixSpan);

    const Ref largeRef = store.reserveRange(80, 8, true);

    if (prefixRef != 0 || largeRef != 8)
        return Result::Error;
    if (store.size() != 88 || store.extentSize() != 88)
        return Result::Error;

    std::array<std::byte, 88> out;
    out.fill(std::byte{0xCC});
    store.copyToPreserveOffsets(ByteSpanRW{out.data(), out.size()});

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
