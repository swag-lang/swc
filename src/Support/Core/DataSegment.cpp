#include "pch.h"
#include "Support/Core/DataSegment.h"

SWC_BEGIN_NAMESPACE();

std::pair<ByteSpan, Ref> DataSegment::addSpan(ByteSpan value)
{
    return addSpan(value, alignof(std::byte));
}

std::pair<ByteSpan, Ref> DataSegment::addSpan(ByteSpan value, uint32_t align)
{
    const std::unique_lock lock(mutex_);
    const auto             res = store_.pushCopySpan(value, align);
    recordAllocation(res.second, static_cast<uint32_t>(value.size()), align);
    return res;
}

std::pair<std::string_view, Ref> DataSegment::addString(const Utf8& value)
{
    const std::unique_lock lock(mutex_);
    if (const auto it = stringMap_.find(value); it != stringMap_.end())
        return it->second;

    Utf8 zeroTerminated = value;
    zeroTerminated.push_back('\0');

    const auto [span, ref] = store_.pushCopySpan(asByteSpan(std::string_view(zeroTerminated)));
    recordAllocation(ref, static_cast<uint32_t>(zeroTerminated.size()), alignof(std::byte));
    const std::string_view view{reinterpret_cast<const char*>(span.data()), value.size()};
    stringMap_[value] = {view, ref};

    return {view, ref};
}

uint32_t DataSegment::addString(uint32_t baseOffset, uint32_t fieldOffset, const Utf8& value)
{
    const std::pair<std::string_view, Ref> res = addString(value);
    addRelocation(baseOffset + fieldOffset, res.second);

    const char** ptrField = ptr<const char*>(baseOffset + fieldOffset);
    *ptrField             = res.first.data();

    return static_cast<uint32_t>(res.first.size());
}

void DataSegment::addRelocation(uint32_t offset, uint32_t targetOffset)
{
    const std::unique_lock lock(mutex_);
    relocations_.push_back({.offset = offset, .targetOffset = targetOffset});
}

bool DataSegment::findAllocation(DataSegmentAllocation& outAllocation, const uint32_t offset) const noexcept
{
    outAllocation = {};

    const std::shared_lock lock(mutex_);
    if (allocations_.empty())
        return false;

    const auto it = std::ranges::upper_bound(allocations_, offset, {}, &DataSegmentAllocation::offset);
    if (it == allocations_.begin())
        return false;

    const auto allocIt = std::prev(it);
    if (offset < allocIt->offset || offset - allocIt->offset >= allocIt->size)
        return false;

    outAllocation = *allocIt;
    return true;
}

uint32_t DataSegment::size() const noexcept
{
    const std::shared_lock lock(mutex_);
    return store_.size();
}

uint32_t DataSegment::extentSize() const noexcept
{
    const std::shared_lock lock(mutex_);
    return store_.extentSize();
}

void DataSegment::copyTo(ByteSpanRW dst) const
{
    const std::shared_lock lock(mutex_);
    store_.copyTo(dst);
}

void DataSegment::copyToPreserveOffsets(ByteSpanRW dst) const
{
    const std::shared_lock lock(mutex_);
    store_.copyToPreserveOffsets(dst);
}

std::pair<uint32_t, std::byte*> DataSegment::reserveBytes(uint32_t size, uint32_t align, bool zeroInit)
{
    const std::unique_lock         lock(mutex_);
    const std::pair<ByteSpan, Ref> res = store_.pushCopySpan(ByteSpan{static_cast<const std::byte*>(nullptr), size}, align);
    std::byte* const               ptr = store_.ptr<std::byte>(res.second);
    if (zeroInit && size)
        std::memset(ptr, 0, size);
    recordAllocation(res.second, size, align);
    return {res.second, ptr};
}

void DataSegment::recordAllocation(const uint32_t offset, const uint32_t size, uint32_t align)
{
    if (!size)
        return;

    if (!align)
        align = 1;

    if (!allocations_.empty())
    {
        const DataSegmentAllocation& last = allocations_.back();
        SWC_ASSERT(last.offset + last.size <= offset);
    }

    allocations_.push_back({
        .offset = offset,
        .size   = size,
        .align  = align,
    });
}

#if SWC_HAS_STATS
size_t DataSegment::memStorageReserved() const
{
    const std::shared_lock lock(mutex_);
    size_t                 result = store_.allocatedBytes();
    result += relocations_.capacity() * sizeof(DataSegmentRelocation);
    result += allocations_.capacity() * sizeof(DataSegmentAllocation);
    result += stringMap_.bucket_count() * sizeof(void*);
    result += stringMap_.size() * (sizeof(std::pair<const std::string, std::pair<std::string_view, uint32_t>>) + sizeof(void*));
    return result;
}
#endif

SWC_END_NAMESPACE();
