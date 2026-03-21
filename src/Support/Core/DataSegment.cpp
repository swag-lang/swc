#include "pch.h"
#include "Support/Core/DataSegment.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint32_t alignUpValue(const uint32_t value, const uint32_t align)
    {
        if (align <= 1)
            return value;
        return (value + (align - 1)) & ~(align - 1);
    }
}

std::pair<ByteSpan, Ref> DataSegment::addSpan(ByteSpan value)
{
    return addSpan(value, alignof(std::byte));
}

std::pair<ByteSpan, Ref> DataSegment::addSpan(ByteSpan value, uint32_t align)
{
    const std::unique_lock lock(mutex_);
    const auto [offset, ptr] = allocateStorageLocked(static_cast<uint32_t>(value.size()), align, false);
    if (value.data() && !value.empty())
        std::memcpy(ptr, value.data(), value.size());
    return {{ptr, value.size()}, offset};
}

std::pair<std::string_view, Ref> DataSegment::addString(const Utf8& value)
{
    const std::unique_lock lock(mutex_);
    if (const auto it = stringMap_.find(value); it != stringMap_.end())
        return it->second;

    Utf8 zeroTerminated = value;
    zeroTerminated.push_back('\0');

    const auto [offset, ptr] = allocateStorageLocked(static_cast<uint32_t>(zeroTerminated.size()), alignof(std::byte), false);
    std::memcpy(ptr, zeroTerminated.data(), zeroTerminated.size());
    const std::string_view view{reinterpret_cast<const char*>(ptr), value.size()};
    stringMap_[value] = {view, offset};

    return {view, offset};
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

Ref DataSegment::findRef(const void* ptr) const noexcept
{
    const std::shared_lock lock(mutex_);
    const Ref              ref = store_.findRef(ptr);
    if (ref != INVALID_REF)
        return ref;
    return findLargeBlockRefLocked(ptr);
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
    if (largeBlocks_.empty())
        return store_.size();
    return currentExtentLocked();
}

uint32_t DataSegment::extentSize() const noexcept
{
    const std::shared_lock lock(mutex_);
    return currentExtentLocked();
}

void DataSegment::copyTo(ByteSpanRW dst) const
{
    const std::shared_lock lock(mutex_);
    if (!largeBlocks_.empty())
    {
        if (dst.empty())
            return;

        std::memset(dst.data(), 0, dst.size_bytes());
        const uint32_t storeExtent = store_.extentSize();
        if (storeExtent)
            store_.copyToPreserveOffsets(ByteSpanRW{dst.data(), storeExtent});
        for (const LargeBlock& block : largeBlocks_)
        {
            SWC_ASSERT(block.offset + block.size <= dst.size_bytes());
            std::memcpy(dst.data() + block.offset, block.storage.get(), block.size);
        }
        return;
    }

    store_.copyTo(dst);
}

void DataSegment::copyToPreserveOffsets(ByteSpanRW dst) const
{
    const std::shared_lock lock(mutex_);
    const uint32_t         storeExtent = store_.extentSize();
    std::memset(dst.data(), 0, dst.size_bytes());
    if (storeExtent)
        store_.copyToPreserveOffsets(ByteSpanRW{dst.data(), storeExtent});
    for (const LargeBlock& block : largeBlocks_)
    {
        SWC_ASSERT(block.offset + block.size <= dst.size_bytes());
        std::memcpy(dst.data() + block.offset, block.storage.get(), block.size);
    }
}

void DataSegment::restoreFromPreserveOffsets(ByteSpan src) const
{
    const std::unique_lock lock(mutex_);
    const uint32_t         storeExtent = store_.extentSize();
    if (storeExtent)
        store_.restoreFromPreserveOffsets(ByteSpan{src.data(), storeExtent});
    for (const LargeBlock& block : largeBlocks_)
    {
        SWC_ASSERT(block.offset + block.size <= src.size_bytes());
        std::memcpy(block.storage.get(), src.data() + block.offset, block.size);
    }
}

std::pair<uint32_t, std::byte*> DataSegment::reserveBytes(uint32_t size, uint32_t align, bool zeroInit)
{
    if (!size)
        return {INVALID_REF, nullptr};

    const std::unique_lock lock(mutex_);
    return allocateStorageLocked(size, align, zeroInit);
}

uint32_t DataSegment::reserveBlock(uint32_t size, uint32_t align, bool zeroInit)
{
    return reserveBytes(size, align, zeroInit).first;
}

uint32_t DataSegment::currentExtentLocked() const noexcept
{
    if (!largeBlocks_.empty())
    {
        const LargeBlock& last = largeBlocks_.back();
        return last.offset + last.size;
    }

    return store_.extentSize();
}

std::pair<uint32_t, std::byte*> DataSegment::allocateStorageLocked(uint32_t size, uint32_t align, bool zeroInit)
{
    if (!size)
        return {INVALID_REF, nullptr};
    if (!align)
        align = 1;

    if (!largeBlocks_.empty() || size > store_.pageSize())
    {
        LargeBlock block;
        block.offset  = alignUpValue(currentExtentLocked(), align);
        block.size    = size;
        block.storage = std::make_unique<std::byte[]>(size);
        if (zeroInit)
            std::memset(block.storage.get(), 0, size);

        const uint32_t   offset = block.offset;
        std::byte* const ptr    = block.storage.get();
        largeBlocks_.push_back(std::move(block));
        recordAllocation(offset, size, align);
        return {offset, ptr};
    }

    const std::pair<ByteSpan, Ref> res = store_.pushCopySpan(ByteSpan{static_cast<const std::byte*>(nullptr), size}, align);
    std::byte* const               ptr = store_.ptr<std::byte>(res.second);
    if (zeroInit)
        std::memset(ptr, 0, size);
    recordAllocation(res.second, size, align);
    return {res.second, ptr};
}

std::byte* DataSegment::findPtrLocked(const Ref ref, const uint32_t size) noexcept
{
    SWC_ASSERT(ref != INVALID_REF);

    if (!largeBlocks_.empty())
    {
        for (const LargeBlock& block : largeBlocks_)
        {
            if (ref < block.offset)
                break;
            if (ref >= block.offset && ref + size <= block.offset + block.size)
                return block.storage.get() + (ref - block.offset);
        }
    }

    SWC_ASSERT(ref + size <= store_.extentSize());
    return store_.ptr<std::byte>(ref);
}

const std::byte* DataSegment::findPtrLocked(const Ref ref, const uint32_t size) const noexcept
{
    SWC_ASSERT(ref != INVALID_REF);

    if (!largeBlocks_.empty())
    {
        for (const LargeBlock& block : largeBlocks_)
        {
            if (ref < block.offset)
                break;
            if (ref >= block.offset && ref + size <= block.offset + block.size)
                return block.storage.get() + (ref - block.offset);
        }
    }

    SWC_ASSERT(ref + size <= store_.extentSize());
    return store_.ptr<std::byte>(ref);
}

Ref DataSegment::findLargeBlockRefLocked(const void* ptr) const noexcept
{
    const auto* bytePtr = static_cast<const std::byte*>(ptr);
    for (const LargeBlock& block : largeBlocks_)
    {
        if (bytePtr >= block.storage.get() && bytePtr < block.storage.get() + block.size)
            return block.offset + static_cast<uint32_t>(bytePtr - block.storage.get());
    }

    return INVALID_REF;
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
    for (const LargeBlock& block : largeBlocks_)
        result += block.size;
    result += relocations_.capacity() * sizeof(DataSegmentRelocation);
    result += allocations_.capacity() * sizeof(DataSegmentAllocation);
    result += stringMap_.bucket_count() * sizeof(void*);
    result += stringMap_.size() * (sizeof(std::pair<const std::string, std::pair<std::string_view, uint32_t>>) + sizeof(void*));
    return result;
}
#endif

SWC_END_NAMESPACE();
