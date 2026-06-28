#include "pch.h"
#include "Support/Core/DataSegment.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool containsLargeBlockRange(const DataSegment::LargeBlock& block, const Ref ref, const uint32_t size) noexcept
    {
        return ref >= block.offset && ref + size <= block.offset + block.size;
    }

    std::byte* findLargeBlockPtr(std::vector<DataSegment::LargeBlock>& blocks, const Ref ref, const uint32_t size) noexcept
    {
        for (DataSegment::LargeBlock& block : blocks)
        {
            if (ref < block.offset)
                break;
            if (containsLargeBlockRange(block, ref, size))
                return block.storage.get() + (ref - block.offset);
        }

        return nullptr;
    }

    const std::byte* findLargeBlockPtr(const std::vector<DataSegment::LargeBlock>& blocks, const Ref ref, const uint32_t size) noexcept
    {
        for (const DataSegment::LargeBlock& block : blocks)
        {
            if (ref < block.offset)
                break;
            if (containsLargeBlockRange(block, ref, size))
                return block.storage.get() + (ref - block.offset);
        }

        return nullptr;
    }

    struct RelocationOffsetProjection
    {
        const std::vector<DataSegmentRelocation>* relocations = nullptr;

        uint32_t operator()(const uint32_t index) const
        {
            return (*relocations)[index].offset;
        }
    };

    struct RelocationIndexLess
    {
        const std::vector<DataSegmentRelocation>* relocations = nullptr;

        bool operator()(const uint32_t lhs, const uint32_t rhs) const
        {
            const uint32_t lhsOffset = (*relocations)[lhs].offset;
            const uint32_t rhsOffset = (*relocations)[rhs].offset;
            if (lhsOffset != rhsOffset)
                return lhsOffset < rhsOffset;
            return lhs < rhs;
        }
    };
}

std::pair<std::span<const std::byte>, Ref> DataSegment::addSpan(std::span<const std::byte> value)
{
    return addSpan(value, alignof(std::byte));
}

std::pair<std::span<const std::byte>, Ref> DataSegment::addSpan(std::span<const std::byte> value, uint32_t align)
{
    const std::unique_lock lock(mutex_);
    const auto [offset, ptr] = allocateStorageLocked(static_cast<uint32_t>(value.size()), align, false);
    if (value.data() && !value.empty())
        std::memcpy(ptr, value.data(), value.size());
    recordAllocation(offset, static_cast<uint32_t>(value.size()), align);
    return {{ptr, value.size()}, offset};
}

std::pair<std::string_view, Ref> DataSegment::addString(const Utf8& value)
{
    const std::unique_lock lock(mutex_);
    const auto             it = stringMap_.find(value);
    if (it != stringMap_.end())
        return it->second;

    Utf8 zeroTerminated = value;
    zeroTerminated.push_back('\0');

    const auto [offset, ptr] = allocateStorageLocked(static_cast<uint32_t>(zeroTerminated.size()), alignof(std::byte), false);
    std::memcpy(ptr, zeroTerminated.data(), zeroTerminated.size());
    recordAllocation(offset, static_cast<uint32_t>(zeroTerminated.size()), alignof(std::byte));
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
    const std::unique_lock lock(relocationsMutex_);
    const uint32_t         relocationIndex = static_cast<uint32_t>(relocations_.size());
    relocations_.push_back({.offset = offset, .kind = DataSegmentRelocationKind::DataSegmentOffset, .targetOffset = targetOffset, .targetShardIndex = INVALID_REF, .targetSymbol = nullptr});
    recordRelocationIndexLocked(relocationIndex);
}

void DataSegment::addRelocation(uint32_t offset, const DataSegmentRef targetRef)
{
    const std::unique_lock lock(relocationsMutex_);
    const uint32_t         relocationIndex = static_cast<uint32_t>(relocations_.size());
    relocations_.push_back({.offset = offset, .kind = DataSegmentRelocationKind::DataSegmentOffset, .targetOffset = targetRef.offset, .targetShardIndex = targetRef.shardIndex, .targetSymbol = nullptr});
    recordRelocationIndexLocked(relocationIndex);
}

void DataSegment::addFunctionRelocation(uint32_t offset, const SymbolFunction* targetSymbol, bool allowUnresolvedFunction)
{
    const std::unique_lock lock(relocationsMutex_);
    const uint32_t         relocationIndex = static_cast<uint32_t>(relocations_.size());
    relocations_.push_back({.offset = offset, .kind = DataSegmentRelocationKind::FunctionSymbol, .targetOffset = INVALID_REF, .targetShardIndex = INVALID_REF, .targetSymbol = targetSymbol, .allowUnresolvedFunction = allowUnresolvedFunction});
    recordRelocationIndexLocked(relocationIndex);
}

Ref DataSegment::findRef(const void* ptr) const noexcept
{
    // Fast path: with no large blocks, findRef only consults the lock-free PagedStore.
    if (!hasLargeBlocks_.load(std::memory_order_acquire))
        return store_.findRef(ptr);

    const std::shared_lock lock(mutex_);
    const Ref              ref = store_.findRef(ptr);
    if (ref != INVALID_REF)
        return ref;
    return findLargeBlockRefLocked(ptr);
}

bool DataSegment::findAllocation(DataSegmentAllocation& outAllocation, const uint32_t offset) const noexcept
{
    outAllocation = {};

    const std::shared_lock lock(allocationsMutex_);
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

void DataSegment::copyTo(std::span<std::byte> dst) const
{
    const std::shared_lock lock(mutex_);
    if (!largeBlocks_.empty())
    {
        if (dst.empty())
            return;

        std::memset(dst.data(), 0, dst.size_bytes());
        const uint32_t storeExtent = store_.extentSize();
        if (storeExtent)
            store_.copyToPreserveOffsets(std::span<std::byte>{dst.data(), storeExtent});
        for (const LargeBlock& block : largeBlocks_)
        {
            SWC_ASSERT(block.offset + block.size <= dst.size_bytes());
            std::memcpy(dst.data() + block.offset, block.storage.get(), block.size);
        }
        return;
    }

    store_.copyTo(dst);
}

void DataSegment::copyToPreserveOffsets(std::span<std::byte> dst) const
{
    const std::shared_lock lock(mutex_);
    const uint32_t         storeExtent = store_.extentSize();
    std::memset(dst.data(), 0, dst.size_bytes());
    if (storeExtent)
        store_.copyToPreserveOffsets(std::span<std::byte>{dst.data(), storeExtent});
    for (const LargeBlock& block : largeBlocks_)
    {
        SWC_ASSERT(block.offset + block.size <= dst.size_bytes());
        std::memcpy(dst.data() + block.offset, block.storage.get(), block.size);
    }
}

void DataSegment::restoreFromPreserveOffsets(std::span<const std::byte> src) const
{
    const std::unique_lock lock(mutex_);
    const uint32_t         storeExtent = store_.extentSize();
    if (storeExtent)
        store_.restoreFromPreserveOffsets(std::span{src.data(), storeExtent});
    for (const LargeBlock& block : largeBlocks_)
    {
        SWC_ASSERT(block.offset + block.size <= src.size_bytes());
        std::memcpy(block.storage.get(), src.data() + block.offset, block.size);
    }
}

std::vector<DataSegmentRelocation> DataSegment::copyRelocations() const
{
    const std::shared_lock lock(relocationsMutex_);
    return relocations_;
}

void DataSegment::copyRelocations(std::vector<DataSegmentRelocation>& outRelocations, const uint32_t offset, const uint32_t size) const
{
    outRelocations.clear();
    if (!size)
        return;

    {
        const std::shared_lock lock(relocationsMutex_);
        if (!relocationsByOffsetDirty_ && relocationsByOffset_.size() == relocations_.size())
        {
            copyRelocationsLocked(outRelocations, offset, size);
            return;
        }
    }

    const std::unique_lock lock(relocationsMutex_);
    rebuildRelocationsByOffsetLocked();
    copyRelocationsLocked(outRelocations, offset, size);
}

bool DataSegment::findRelocation(DataSegmentRelocation& outRelocation, const uint32_t offset, const DataSegmentRelocationKind kind) const
{
    outRelocation = {};

    {
        const std::shared_lock lock(relocationsMutex_);
        if (!relocationsByOffsetDirty_ && relocationsByOffset_.size() == relocations_.size())
            return findRelocationLocked(outRelocation, offset, kind);
    }

    const std::unique_lock lock(relocationsMutex_);
    rebuildRelocationsByOffsetLocked();
    return findRelocationLocked(outRelocation, offset, kind);
}

bool DataSegment::hasRelocations(const uint32_t offset, const uint32_t size) const
{
    if (!size)
        return false;

    {
        const std::shared_lock lock(relocationsMutex_);
        if (!relocationsByOffsetDirty_ && relocationsByOffset_.size() == relocations_.size())
            return hasRelocationsLocked(offset, size);
    }

    const std::unique_lock lock(relocationsMutex_);
    rebuildRelocationsByOffsetLocked();
    return hasRelocationsLocked(offset, size);
}

void DataSegment::copyRelocationsLocked(std::vector<DataSegmentRelocation>& outRelocations, const uint32_t offset, const uint32_t size) const
{
    const RelocationOffsetProjection projection{.relocations = &relocations_};
    const auto                       begin = std::ranges::lower_bound(relocationsByOffset_, offset, {}, projection);

    for (auto it = begin; it != relocationsByOffset_.end(); ++it)
    {
        const DataSegmentRelocation& relocation = relocations_[*it];
        if (relocation.offset - offset >= size)
            break;

        outRelocations.push_back(relocation);
    }
}

bool DataSegment::findRelocationLocked(DataSegmentRelocation& outRelocation, const uint32_t offset, const DataSegmentRelocationKind kind) const
{
    const RelocationOffsetProjection projection{.relocations = &relocations_};
    auto                             it = std::ranges::lower_bound(relocationsByOffset_, offset, {}, projection);
    while (it != relocationsByOffset_.end())
    {
        const DataSegmentRelocation& relocation = relocations_[*it];
        if (relocation.offset != offset)
            break;
        if (relocation.kind == kind)
        {
            outRelocation = relocation;
            return true;
        }
        ++it;
    }

    return false;
}

bool DataSegment::hasRelocationsLocked(const uint32_t offset, const uint32_t size) const
{
    const RelocationOffsetProjection projection{.relocations = &relocations_};
    const auto                       it = std::ranges::lower_bound(relocationsByOffset_, offset, {}, projection);
    if (it == relocationsByOffset_.end())
        return false;

    const DataSegmentRelocation& relocation = relocations_[*it];
    return relocation.offset - offset < size;
}

std::mutex& DataSegment::allocationMutex(const uint32_t allocationOffset) const
{
    const std::scoped_lock lock(allocationMutexesMutex_);
    auto&                  mutex = allocationMutexes_[allocationOffset];
    if (!mutex)
        mutex = std::make_unique<std::mutex>();
    return *mutex;
}

std::pair<uint32_t, std::byte*> DataSegment::reserveBytes(uint32_t size, uint32_t align, bool zeroInit)
{
    if (!size)
        return {INVALID_REF, nullptr};

    const std::unique_lock lock(mutex_);
    const auto             res = allocateStorageLocked(size, align, zeroInit);
    recordAllocation(res.first, size, align);
    return res;
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
        block.offset  = Math::alignUpU32(currentExtentLocked(), align);
        block.size    = size;
        block.storage = std::make_unique<std::byte[]>(size);
        if (zeroInit)
            std::memset(block.storage.get(), 0, size);

        const uint32_t offset    = block.offset;
        std::byte*     ptr       = block.storage.get();
        const auto     begin     = reinterpret_cast<uintptr_t>(ptr);
        largeBlockRanges_[begin] = {
            .offsetEnd   = begin + size,
            .blockOffset = offset,
        };
        largeBlocks_.push_back(std::move(block));
        // Publish that large blocks now exist so lock-free readers fall back to the locked path
        // (which consults largeBlocks_). Release pairs with the acquire load in ptr()/findRef().
        hasLargeBlocks_.store(true, std::memory_order_release);
        return {offset, ptr};
    }

    const std::pair<std::span<const std::byte>, Ref> res = store_.pushCopySpan(std::span{static_cast<const std::byte*>(nullptr), size}, align);
    std::byte* const                                 ptr = store_.ptr<std::byte>(res.second);
    if (zeroInit)
        std::memset(ptr, 0, size);
    return {res.second, ptr};
}

std::byte* DataSegment::findPtrLocked(const Ref ref, const uint32_t size) noexcept
{
    SWC_ASSERT(ref != INVALID_REF);

    if (!largeBlocks_.empty())
    {
        if (std::byte* ptr = findLargeBlockPtr(largeBlocks_, ref, size))
            return ptr;
    }

    SWC_ASSERT(ref + size <= store_.extentSize());
    return store_.ptr<std::byte>(ref);
}

const std::byte* DataSegment::findPtrLocked(const Ref ref, const uint32_t size) const noexcept
{
    SWC_ASSERT(ref != INVALID_REF);

    if (!largeBlocks_.empty())
    {
        if (const std::byte* ptr = findLargeBlockPtr(largeBlocks_, ref, size))
            return ptr;
    }

    SWC_ASSERT(ref + size <= store_.extentSize());
    return store_.ptr<std::byte>(ref);
}

Ref DataSegment::findLargeBlockRefLocked(const void* ptr) const noexcept
{
    if (!ptr || largeBlockRanges_.empty())
        return INVALID_REF;

    const auto address = reinterpret_cast<uintptr_t>(ptr);
    const auto nextIt  = largeBlockRanges_.upper_bound(address);
    if (nextIt == largeBlockRanges_.begin())
        return INVALID_REF;

    const auto it = std::prev(nextIt);
    if (address >= it->second.offsetEnd)
        return INVALID_REF;

    return it->second.blockOffset + static_cast<uint32_t>(address - it->first);
}

void DataSegment::rebuildRelocationsByOffsetLocked() const
{
    if (!relocationsByOffsetDirty_ && relocationsByOffset_.size() == relocations_.size())
        return;

    relocationsByOffset_.resize(relocations_.size());
    std::ranges::iota(relocationsByOffset_, 0u);
    const RelocationIndexLess sortRelocations{.relocations = &relocations_};
    std::ranges::sort(relocationsByOffset_, sortRelocations);
    relocationsByOffsetDirty_ = false;
}

void DataSegment::recordRelocationIndexLocked(uint32_t index)
{
    SWC_ASSERT(index + 1 == relocations_.size());

    if (relocationsByOffsetDirty_ || relocationsByOffset_.size() + 1 != relocations_.size())
    {
        relocationsByOffsetDirty_ = true;
        return;
    }

    const RelocationIndexLess sortRelocations{.relocations = &relocations_};
    if (!relocationsByOffset_.empty() && sortRelocations(index, relocationsByOffset_.back()))
    {
        relocationsByOffsetDirty_ = true;
        return;
    }

    relocationsByOffset_.push_back(index);
}

void DataSegment::recordAllocation(const uint32_t offset, const uint32_t size, uint32_t align)
{
    if (!size)
        return;

    const std::unique_lock lock(allocationsMutex_);

    if (!align)
        align = 1;

    if (!allocations_.empty())
    {
        const DataSegmentAllocation& last = allocations_.back();
        SWC_ASSERT(last.offset + last.size <= offset);
    }

    allocations_.push_back({.offset = offset, .size = size, .align = align});
}

SWC_END_NAMESPACE();
